/// Persisted broadcast queue: keeps an event on its way to every relay it is
/// meant for across offline periods, delayed remote signing and restarts.
///
/// ```dart
/// final queue = PendingBroadcastDelivery(
///   store: cacheManager,
///   accounts: accounts,
///   urlLists: urlLists,
///   isEventInFlight: relayManager.isBroadcasting,
///   send: (event, relayUrl, auth) => publishTo(event, relayUrl, auth),
/// );
/// await queue.enqueueSpecificRelayBroadcast(
///   event: event,
///   relayUrls: ['wss://relay.example.com'],
///   requiresInteractiveSigning: false,
/// );
/// queue.startPeriodicRetry(
///   connectedRelayUrls: () => connectedUrls,
///   reconnectRelay: (relayUrl) => reconnect(relayUrl),
/// );
/// ```
library;

export 'src/delivery_policy.dart';
export 'src/delivery_records.dart';
export 'src/delivery_response.dart';
export 'src/delivery_store.dart';
export 'src/event_delivery_snapshot.dart';
export 'src/pending_broadcast_delivery.dart';
