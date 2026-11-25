import 'package:dostr_core/dostr_core.dart' show RelayUrl;
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast.dart';

import 'queued_publish.dart';
import 'replaceable.dart';

/// Sembast-backed persistent store for [QueuedPublish] records.
///
/// All writes are serialized through sembast transactions. The store name is
/// caller-provided so several queues can coexist in the same database.
class QueueStore {
  final Database _db;
  final StoreRef<String, Map<String, Object?>> _store;

  QueueStore({required Database db, required String storeName})
    : _db = db,
      _store = stringMapStoreFactory.store(storeName);

  Future<QueuedPublish?> get(String key) async {
    final map = await _store.record(key).get(_db);
    if (map == null) return null;
    return QueuedPublish.fromMap(_normalize(map));
  }

  /// Writes [record], then, in the same transaction, supersedes every record
  /// of an older version of the same replaceable or addressable event that
  /// is still owed an attempt, [record] included, once newer versions head to
  /// all its relays. Returns [record] as stored.
  Future<QueuedPublish> put(QueuedPublish record) {
    return _db.transaction((txn) async {
      await _store.record(record.key).put(txn, record.toMap());
      final address = replaceableAddress(record.event);
      if (address == null) return record;

      final sameAuthorAndKind = Finder(
        filter: Filter.custom((r) {
          final event = (r.value as Map)['event'] as Map;
          return event['kind'] == record.event.kind &&
              event['pubkey'] == record.event.pubkey;
        }),
      );
      final versions = (await _store.find(txn, finder: sameAuthorAndKind))
          .map((r) => QueuedPublish.fromMap(_normalize(r.value)))
          .where((r) => replaceableAddress(r.event) == address)
          .toList();
      final newest = versions
          .map((r) => r.event)
          .reduce((a, b) => replaces(b, a) ? b : a);

      var stored = record;
      for (final version in versions) {
        final QueuedPublish superseded;
        if (version.supersededBy == null) {
          final owed =
              version.status == QueuedPublishStatus.pending ||
              version.forcedRelays != null;
          if (!owed) continue;
          final newer = [
            for (final other in versions)
              if (replaces(other.event, version.event)) other,
          ];
          if (newer.isEmpty || !_covered(version, newer)) continue;
          superseded = version.copyWith(
            supersededBy: newest.id,
            clearPendingRelaySet: true,
            clearForcedRelays: true,
          );
        } else if (version.pendingRelaySet != null) {
          superseded = version.copyWith(clearPendingRelaySet: true);
        } else {
          continue;
        }
        await _store.record(version.key).put(txn, superseded.toMap());
        if (version.key == record.key) stored = superseded;
      }
      return stored;
    });
  }

  /// Atomically read-modify-write a record. The mutator runs inside a sembast
  /// transaction; returning null leaves the record unchanged.
  Future<QueuedPublish?> update(
    String key,
    QueuedPublish? Function(QueuedPublish current) mutate,
  ) async {
    return _db.transaction((txn) async {
      final raw = await _store.record(key).get(txn);
      if (raw == null) return null;
      final current = QueuedPublish.fromMap(_normalize(raw));
      final next = mutate(current);
      if (next == null) return current;
      await _store.record(key).put(txn, next.toMap());
      return next;
    });
  }

  /// Whether the [newer] versions hold, or are still headed to, every relay
  /// [version] owes. A relay set still to resolve only covers the same set.
  static bool _covered(QueuedPublish version, List<QueuedPublish> newer) {
    final relays = <RelayUrl>{};
    final sets = <UrlSet>{};
    for (final other in newer) {
      relays.addAll(other.ackedRelays);
      if (other.status != QueuedPublishStatus.pending) continue;
      relays.addAll(other.remainingRelays);
      if (other.pendingRelaySet case final set?) sets.add(set);
    }
    final owedSet = version.pendingRelaySet;
    return (owedSet == null || sets.contains(owedSet)) &&
        [
          ...version.remainingRelays,
          ...?version.forcedRelays,
        ].every(relays.contains);
  }

  /// Deletes every record queued under [account]. Records with no account
  /// never match. Returns the number of records removed.
  Future<int> deleteByAccount(String account) => _store.delete(
    _db,
    finder: Finder(filter: Filter.equals('pubkey', account)),
  );

  /// Deletes every record in this store. Other stores in the database are
  /// left untouched. Returns the number of records removed.
  Future<int> deleteAll() => _store.delete(_db);

  /// Records eligible for an attempt right now: either still pending (relay
  /// set unresolved included), or terminal but carrying a
  /// [QueuedPublish.forcedRelays] override that hasn't been consumed yet.
  /// Sorted in the order they were queued.
  Future<List<QueuedPublish>> findDue({required int now}) async {
    final finder = Finder(
      filter: Filter.custom((record) {
        final m = record.value as Map;
        final nextAttemptAt = m['nextAttemptAt'] as int;
        if (nextAttemptAt > now) return false;
        if (m['supersededBy'] != null) return m['forcedRelays'] != null;
        if (m['cancelledAt'] != null) return m['forcedRelays'] != null;
        if (m['pendingRelaySet'] != null) return true;
        if (m['deliveredAt'] == null && m['failedAt'] == null) return true;
        return m['forcedRelays'] != null;
      }),
      sortOrders: [SortOrder('createdAt')],
    );
    final records = await _store.find(_db, finder: finder);
    return records
        .map((r) => QueuedPublish.fromMap(_normalize(r.value)))
        .toList(growable: false);
  }

  Future<List<QueuedPublish>> findAll() async {
    final records = await _store.find(_db);
    return records
        .map((r) => QueuedPublish.fromMap(_normalize(r.value)))
        .toList(growable: false);
  }

  Stream<QueuedPublish?> watch(String key) {
    return _store
        .record(key)
        .onSnapshot(_db)
        .map(
          (snap) => snap == null
              ? null
              : QueuedPublish.fromMap(_normalize(snap.value)),
        );
  }

  Stream<List<QueuedPublish>> watchPending() {
    final finder = Finder(
      filter: Filter.or([
        Filter.notNull('pendingRelaySet'),
        Filter.and([
          Filter.equals('deliveredAt', null),
          Filter.equals('failedAt', null),
        ]),
      ]),
    );
    return _store
        .query(finder: finder)
        .onSnapshots(_db)
        .map(
          (snaps) => snaps
              .map((s) => QueuedPublish.fromMap(_normalize(s.value)))
              .where((r) => r.status == QueuedPublishStatus.pending)
              .toList(growable: false),
        );
  }

  /// Sembast hands back `Map<String, Object?>`; QueuedPublish.fromMap expects
  /// `Map<String, dynamic>`. The cast is shallow on purpose: nested maps stay
  /// as `Map<dynamic, dynamic>` and the model handles them.
  Map<String, dynamic> _normalize(Map<String, Object?> raw) =>
      Map<String, dynamic>.from(raw);
}
