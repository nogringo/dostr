import 'relay.dart';
import 'relay_connection_key.dart';
import 'relay_stats.dart';

/// One connection of a `RelayManager`, which alone opens, closes and updates
/// it.
abstract interface class RelayConnectivity {
  /// identifies this connection: the relay and the identity bound to it
  RelayConnectionKey get key;

  /// relay url/identifier
  String get url;

  /// relay data including connection state
  Relay get relay;

  /// relay stats
  RelayStats get stats;

  /// whether its socket is open
  bool get isConnected;
}
