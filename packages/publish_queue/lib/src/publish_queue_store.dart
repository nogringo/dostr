import 'queued_publish.dart';

/// Where a `PublishQueue` keeps its records, so that they survive a restart.
/// A record is identified by its [QueuedPublish.key].
///
/// The queue reads every record once, on its first use, then keeps them in
/// memory and only writes. So a store serves one queue at a time: what is
/// written to it from elsewhere is only seen by the next queue that reads it.
///
/// [QueuedPublish.toMap] and [QueuedPublish.fromMap] turn a record into
/// JSON-compatible values and back.
abstract interface class PublishQueueStore {
  /// Every stored record.
  Future<List<QueuedPublish>> readAll();

  /// Stores [records] in one atomic write, each in place of the record with
  /// the same key. Completes once they are durable.
  Future<void> put(List<QueuedPublish> records);

  /// Deletes the records with these [keys], those that exist. Completes once
  /// the deletion is durable.
  Future<void> delete(List<String> keys);
}
