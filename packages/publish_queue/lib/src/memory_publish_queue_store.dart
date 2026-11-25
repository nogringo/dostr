import 'publish_queue_store.dart';
import 'queued_publish.dart';

/// A [PublishQueueStore] that lives as long as the process, for tests and for
/// queues that need not survive a restart.
class MemoryPublishQueueStore implements PublishQueueStore {
  final Map<String, QueuedPublish> _records = {};

  @override
  Future<List<QueuedPublish>> readAll() async => _records.values.toList();

  @override
  Future<void> put(List<QueuedPublish> records) async {
    for (final record in records) {
      _records[record.key] = record;
    }
  }

  @override
  Future<void> delete(List<String> keys) async => keys.forEach(_records.remove);
}
