import 'relay_connection_key.dart';

/// Runs a protocol of its own over the relay connections, such as NIP-77
/// negentropy. Once added with `RelayManager.addProtocolHandler`, it receives
/// what `RelayManager` does not handle itself.
abstract class RelayProtocolHandler {
  /// A relay message of a type `RelayManager` does not know, such as NEG-MSG.
  /// Returns whether this handler took it.
  bool onMessage(RelayConnectionKey key, List<dynamic> message) => false;

  /// A CLOSED for [subscriptionId]. Returns whether this handler owns that
  /// subscription, in which case `RelayManager` does not treat it as a REQ.
  bool onClosed(
    RelayConnectionKey key,
    String subscriptionId,
    String? message,
  ) => false;

  /// A NOTICE from the relay behind [key].
  void onNotice(RelayConnectionKey key, String message) {}

  /// Whether this handler still needs the connection behind [key], which keeps
  /// `RelayManager.closeIdleConnections` from closing it.
  bool hasWorkOn(RelayConnectionKey key) => false;
}
