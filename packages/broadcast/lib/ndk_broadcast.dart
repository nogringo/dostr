/// Broadcasts for NDK: sign events and publish them to the outbox relays of
/// their author and the inbox relays of the pubkeys they tag, retrying the
/// relays that did not ack them.
///
/// ```dart
/// final broadcast = Broadcast(
///   broadcastSender: sender,
///   accounts: accounts,
///   cacheManager: cache,
///   pendingDelivery: pendingDelivery,
/// );
/// final response = broadcast.broadcast(nostrEvent: note);
/// final outcomes = await response.broadcastDoneFuture;
/// ```
library;

export 'src/broadcast.dart';
export 'src/broadcast_exceptions.dart';
export 'src/broadcast_response.dart';
export 'src/broadcast_sender.dart';
export 'src/broadcast_url_set.dart';
export 'src/delivery_responses.dart';
export 'src/reaction.dart';
