import 'relay_connection_key.dart';

/// One connection of a `RelayManager`, as it stood when it was read: nothing
/// changes it afterwards. Read it again from the `RelayManager` for its state
/// now.
abstract interface class RelayConnectivity {
  /// identifies this connection: the relay and the identity bound to it
  RelayConnectionKey get key;

  /// whether its socket is open
  bool get isConnected;

  /// whether its socket is being opened
  bool get isConnecting;
}
