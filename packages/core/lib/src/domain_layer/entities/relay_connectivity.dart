import 'package:dostr_relay_url/dostr_relay_url.dart';

import 'relay.dart';
import 'relay_connection_key.dart';
import 'relay_stats.dart';

/// One connection of a `RelayManager`, as it stood when it was read: nothing
/// changes it afterwards. Read it again from the `RelayManager` for its state
/// now.
abstract interface class RelayConnectivity {
  /// identifies this connection: the relay and the identity bound to it
  RelayConnectionKey get key;

  RelayUrl get url;

  /// relay data including connection state
  Relay get relay;

  /// relay stats
  RelayStats get stats;

  /// whether its socket is open
  bool get isConnected;
}
