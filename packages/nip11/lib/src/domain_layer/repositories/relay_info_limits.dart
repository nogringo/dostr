import '../entities/relay_info.dart';
import 'relay_info_repository.dart';

/// The limits of each relay, read from its NIP-11 document, in the shape the
/// `subscriptionLimit` and `messageLengthLimit` of a `dostr_core`
/// `RelayManager` take.
///
/// ```dart
/// final relays = RelayManager(
///   nostrTransportFactory: WebSocketClientNostrTransportFactory(),
///   subscriptionLimit: relayInfo.maxSubscriptions,
///   messageLengthLimit: relayInfo.maxMessageLength,
/// );
/// ```
extension RelayInfoLimits on RelayInfoRepository {
  /// `limitation.max_subscriptions` of the relay at [url], null when it
  /// publishes none or could not be reached.
  Future<int?> maxSubscriptions(String url) async =>
      (await _limitationOf(url))?.maxSubscriptions;

  /// `limitation.max_message_length` of the relay at [url], null when it
  /// publishes none or could not be reached.
  Future<int?> maxMessageLength(String url) async =>
      (await _limitationOf(url))?.maxMessageLength;

  Future<RelayLimitation?> _limitationOf(String url) async {
    try {
      return (await getRelayInfo(url))?.limitation;
    } catch (_) {
      return null;
    }
  }
}
