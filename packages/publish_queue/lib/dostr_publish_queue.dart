/// An offline-first queue in front of the publishes of dostr_core: each event
/// is stored in a `PublishQueueStore` first, then sent until every relay of its
/// dostr_url_set `UrlSet` accepts it, refuses it for good, or stays
/// unreachable while online.
library;

export 'src/memory_publish_queue_store.dart' show MemoryPublishQueueStore;
export 'src/publish_queue.dart' show PublishFn, PublishQueue;
export 'src/publish_queue_store.dart' show PublishQueueStore;
export 'src/queued_publish.dart' show QueuedPublishStatus, QueuedPublish;
