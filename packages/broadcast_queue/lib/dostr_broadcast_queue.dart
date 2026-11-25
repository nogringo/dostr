/// An offline-first queue in front of the publishes of dostr_core: each event
/// is stored in sembast first, then sent until every relay of its dostr_url_set
/// `UrlSet` accepts it, refuses it for good, or stays unreachable while online.
library;

export 'src/broadcast_queue.dart' show BroadcastFn, BroadcastQueue;
export 'src/queued_broadcast.dart' show BroadcastStatus, QueuedBroadcast;
