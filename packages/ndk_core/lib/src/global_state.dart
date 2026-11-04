import '../domain_layer/entities/broadcast_state.dart';
import '../domain_layer/entities/relay_connection_key.dart';
import '../domain_layer/entities/relay_connectivity.dart';
import '../domain_layer/usecases/relay_manager.dart';
import 'request_state.dart';

/// What a [RelayManager] keeps track of. Internal to ndk_core.
class GlobalState {
  /// holds the state of all in flight requests
  /// key: request Id
  final Map<String, RequestState> inFlightRequests = {};

  /// hold state information for a broadcast
  /// key: event Id
  /// value: one state per broadcast call, the same event can be in flight
  /// several times at once
  final Map<String, List<BroadcastState>> inFlightBroadcasts = {};

  /// touched relays - connected, connecting, disconnected
  /// key: relay url and identity bound to the connection
  /// value: relay connectivity
  final Map<RelayConnectionKey, RelayConnectivity> relays = {};

  /// clean urls of relays that are blocked
  final Set<String> blockedRelays = {};
}

final _states = Expando<GlobalState>();

/// The state behind [manager], for ndk_core's own tests to set up what the
/// public API cannot reach.
GlobalState relayManagerState(RelayManager manager) => _states[manager]!;

void bindRelayManagerState(RelayManager manager, GlobalState state) =>
    _states[manager] = state;
