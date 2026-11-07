import 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_state.dart';
import 'package:ndk_core/domain_layer/entities/relay_failure.dart';

/// The [DeliveryResponse] that [PendingBroadcastDelivery] keeps of a
/// [RelayBroadcastResponse].
extension RelayBroadcastResponseDelivery on RelayBroadcastResponse {
  DeliveryResponse toDeliveryResponse() => DeliveryResponse(
    relayUrl: relayUrl,
    accepted: okReceived && broadcastSuccessful,
    message: msg,
    failure: failure?.toString(),
    identityNotAllowed: failure?.kind == RelayFailureKind.identityNotAllowed,
  );
}
