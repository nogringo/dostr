import 'dart:async';

import 'package:dostr_core/dostr_core.dart' show RelayUrl;
import 'package:dostr_url_set/dostr_url_set.dart';

import 'publish_queue_store.dart';
import 'queued_publish.dart';
import 'replaceable.dart';

/// The records of a [PublishQueueStore], read once and kept in memory.
///
/// Writes run one at a time. Each is computed from the records in memory and
/// applied there only once the backend stored it, so a failed write changes
/// nothing.
class QueueStore {
  final PublishQueueStore _backend;
  final Map<String, QueuedPublish> _records = {};
  final StreamController<Set<String>> _changes = StreamController.broadcast(
    sync: true,
  );
  Future<void>? _loading;
  Future<void> _writing = Future.value();

  QueueStore(this._backend);

  /// Completes once the writes started so far are done.
  Future<void> get idle => _writing;

  Future<QueuedPublish?> get(String key) async {
    await _ensureLoaded();
    return _records[key];
  }

  /// Writes [record], and supersedes, in the same write, every record of an
  /// older version of the same replaceable or addressable event that is still
  /// owed an attempt, [record] included, once newer versions head to all its
  /// relays. Returns [record] as stored.
  Future<QueuedPublish> put(QueuedPublish record) => _serialized(() async {
    final address = replaceableAddress(record.event);
    if (address == null) {
      await _store([record]);
      return record;
    }

    final versions = [
      for (final other in _records.values)
        if (other.key != record.key &&
            replaceableAddress(other.event) == address)
          other,
      record,
    ];
    final newest = versions
        .map((r) => r.event)
        .reduce((a, b) => replaces(b, a) ? b : a);

    final written = {record.key: record};
    for (final version in versions) {
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
        written[version.key] = version.copyWith(
          supersededBy: newest.id,
          clearPendingRelaySet: true,
          clearForcedRelays: true,
        );
      } else if (version.pendingRelaySet != null) {
        written[version.key] = version.copyWith(clearPendingRelaySet: true);
      }
    }
    await _store(written.values.toList());
    return written[record.key]!;
  });

  /// Read-modify-write of the record at [key], atomic with the other writes.
  /// Returning null from [mutate] leaves the record unchanged.
  Future<QueuedPublish?> update(
    String key,
    QueuedPublish? Function(QueuedPublish current) mutate,
  ) => _serialized(() async {
    final current = _records[key];
    if (current == null) return null;
    final next = mutate(current);
    if (next == null) return current;
    await _store([next]);
    return next;
  });

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
  /// never match.
  Future<void> deleteByAccount(String account) => _serialized(
    () => _remove([
      for (final record in _records.values)
        if (record.account == account) record.key,
    ]),
  );

  Future<void> deleteAll() =>
      _serialized(() => _remove(_records.keys.toList()));

  /// Records eligible for an attempt right now: either still pending (relay
  /// set unresolved included), or terminal but carrying a
  /// [QueuedPublish.forcedRelays] override that hasn't been consumed yet.
  /// Sorted in the order they were queued.
  Future<List<QueuedPublish>> findDue({required int now}) async {
    await _ensureLoaded();
    return _inQueueOrder(
      _records.values.where(
        (r) =>
            r.nextAttemptAt <= now &&
            (r.status == QueuedPublishStatus.pending || r.forcedRelays != null),
      ),
    );
  }

  Future<List<QueuedPublish>> findAll() async {
    await _ensureLoaded();
    return _inQueueOrder(_records.values);
  }

  Stream<QueuedPublish?> watch(String key) =>
      _watch((written) => written.contains(key), () => _records[key]);

  Stream<List<QueuedPublish>> watchPending() {
    var shown = <String>{};
    return _watch(
      (written) => written.any(
        (key) =>
            shown.contains(key) ||
            _records[key]?.status == QueuedPublishStatus.pending,
      ),
      () {
        final pending = _inQueueOrder(
          _records.values.where((r) => r.status == QueuedPublishStatus.pending),
        );
        shown = {for (final r in pending) r.key};
        return pending;
      },
    );
  }

  /// [read] once listened to, then after every write whose keys [concerns].
  Stream<T> _watch<T>(
    bool Function(Set<String> written) concerns,
    T Function() read,
  ) {
    StreamSubscription<Set<String>>? changes;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        changes = _changes.stream.listen((written) {
          if (concerns(written)) controller.add(read());
        });
        _ensureLoaded().then(
          (_) => controller.add(read()),
          onError: controller.addError,
        );
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  Future<void> _ensureLoaded() => _loading ??= _backend.readAll().then(
    (records) {
      for (final record in records) {
        _records[record.key] = record;
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      _loading = null;
      Error.throwWithStackTrace(error, stackTrace);
    },
  );

  /// Runs [write] once the records are loaded and the writes before it are
  /// done.
  Future<T> _serialized<T>(Future<T> Function() write) {
    final result = _writing.then((_) async {
      await _ensureLoaded();
      return write();
    });
    _writing = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _store(List<QueuedPublish> records) async {
    await _backend.put(records);
    for (final record in records) {
      _records[record.key] = record;
    }
    _changes.add({for (final record in records) record.key});
  }

  Future<void> _remove(List<String> keys) async {
    if (keys.isEmpty) return;
    await _backend.delete(keys);
    keys.forEach(_records.remove);
    _changes.add(keys.toSet());
  }

  /// [records] by [QueuedPublish.createdAt], and at the same time in the order
  /// they were read or first stored.
  static List<QueuedPublish> _inQueueOrder(Iterable<QueuedPublish> records) {
    final indexed = records.indexed.toList()
      ..sort((a, b) {
        final byCreation = a.$2.createdAt.compareTo(b.$2.createdAt);
        return byCreation != 0 ? byCreation : a.$1.compareTo(b.$1);
      });
    return [for (final (_, record) in indexed) record];
  }
}
