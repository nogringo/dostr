import '../connections/relay_connection_key.dart';

/// Runs a protocol of its own over the relay connections, such as NIP-77
/// negentropy.
///
/// Add it with `addProtocolHandler`, from `package:dostr_core/protocol.dart`.
/// It then receives what `RelayManager` does not handle itself, and sends its
/// own messages with `send`.
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

  /// Whether this handler still needs the connection behind [key]. A
  /// connection it needs is not closed as idle.
  bool hasWorkOn(RelayConnectionKey key) => false;
}
