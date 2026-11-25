import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:sembast/sembast.dart';

/// A [PublishQueueStore] in the sembast store of [db] named `storeName`.
///
/// Records are stored as [QueuedPublish.toMap] gives them, under their
/// [QueuedPublish.key], as `broadcast_queue_shim_for_ndk` stored them: its
/// queues load unchanged with the same database and store name. The other
/// stores of [db] are left untouched.
///
/// Closing [db] is up to the caller, once the queue is disposed.
class SembastPublishQueueStore implements PublishQueueStore {
  final Database _db;
  final StoreRef<String, Map<String, Object?>> _store;

  SembastPublishQueueStore(Database db, {String storeName = 'broadcasts'})
    : _db = db,
      _store = stringMapStoreFactory.store(storeName);

  @override
  Future<List<QueuedPublish>> readAll() async => [
    for (final record in await _store.find(_db))
      QueuedPublish.fromMap(Map<String, dynamic>.from(record.value)),
  ];

  @override
  Future<void> put(List<QueuedPublish> records) => _db.transaction((txn) async {
    for (final record in records) {
      await _store.record(record.key).put(txn, record.toMap());
    }
  });

  @override
  Future<void> delete(List<String> keys) => _store.records(keys).delete(_db);
}
