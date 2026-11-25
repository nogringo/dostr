import 'dart:async';

import 'publish_queue_store.dart';
import 'queued_publish.dart';
import 'replaceable.dart';

/// What the newer versions of a replaceable or addressable event do with the
/// relays an older version still owes.
enum Coverage {
  /// At least one relay gets no newer version.
  none,

  /// Newer versions hold, or are still headed to, every relay.
  headedTo,

  /// Newer versions hold every relay.
  held,
}

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

  /// Writes the record [build] makes of the one stored at [key], or of null,
  /// atomic with the other writes. A pending record whose relays all hold a
  /// newer version is stored superseded. Returns the record as stored.
  Future<QueuedPublish> put(
    String key,
    Future<QueuedPublish> Function(QueuedPublish? existing) build,
  ) => _serialized(() async {
    final record = await build(_records[key]);
    final stored = _supersededIfHeld(record) ?? record;
    await _store([stored]);
    return stored;
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

  /// What the newer versions of [record] do with the relays it owes. Always
  /// [Coverage.none] for a record that is not pending or has a push queued by
  /// `republish`. Reads the records in memory: call it once they are loaded.
  Coverage coverage(QueuedPublish record) =>
      _coverage(record, _newerVersions(record));

  /// Marks the record at [key] superseded if newer versions hold every relay
  /// it owes.
  Future<void> supersede(String key) => update(key, _supersededIfHeld);

  QueuedPublish? _supersededIfHeld(QueuedPublish record) {
    final newer = _newerVersions(record);
    if (_coverage(record, newer) != Coverage.held) return null;
    final newest = newer
        .map((r) => r.event)
        .reduce((a, b) => replaces(b, a) ? b : a);
    return record.copyWith(supersededBy: newest.id);
  }

  List<QueuedPublish> _newerVersions(QueuedPublish record) {
    final address = replaceableAddress(record.event);
    if (address == null) return const [];
    return [
      for (final other in _records.values)
        if (replaceableAddress(other.event) == address &&
            replaces(other.event, record.event))
          other,
    ];
  }

  /// A relay set still to resolve is only covered by a pending newer version
  /// that has the same set to resolve.
  static Coverage _coverage(QueuedPublish record, List<QueuedPublish> newer) {
    final set = record.pendingRelaySet;
    final owed = record.remainingRelays;
    if (newer.isEmpty ||
        record.status != QueuedPublishStatus.pending ||
        record.forcedRelays != null ||
        (set == null && owed.isEmpty)) {
      return Coverage.none;
    }
    final held = {for (final other in newer) ...other.ackedRelays};
    if (set == null && owed.every(held.contains)) return Coverage.held;
    final pending = [
      for (final other in newer)
        if (other.status == QueuedPublishStatus.pending) other,
    ];
    final headedTo = {
      ...held,
      for (final other in pending) ...other.remainingRelays,
    };
    final setCovered =
        set == null || pending.any((other) => other.pendingRelaySet == set);
    return setCovered && owed.every(headedTo.contains)
        ? Coverage.headedTo
        : Coverage.none;
  }

  /// Deletes the record at [key] and returns it, or null if there is none.
  Future<QueuedPublish?> delete(String key) => _serialized(() async {
    final record = _records[key];
    if (record != null) await _remove([key]);
    return record;
  });

  /// Deletes the records that are settled, with no push queued by
  /// `republish`, and were created before [createdBefore].
  Future<void> deleteSettled({required int createdBefore}) => _serialized(
    () => _remove([
      for (final record in _records.values)
        if (record.createdAt < createdBefore &&
            record.status != QueuedPublishStatus.pending &&
            record.forcedRelays == null)
          record.key,
    ]),
  );

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
