import 'relay_manager.dart';
import 'relay_auth.dart';
import 'relay_broadcasts.dart';
import 'relay_connections.dart';
import 'relay_requests.dart';

/// The pieces a [RelayManager] is made of. Internal to dostr_core.
final class RelayManagerParts {
  final RelayAuth auth;
  final RelayConnections connections;
  final RelayRequests requests;
  final RelayBroadcasts broadcasts;

  const RelayManagerParts({
    required this.auth,
    required this.connections,
    required this.requests,
    required this.broadcasts,
  });
}

// Dart has no package-private members: RelayReqs, RelayPublishes and the tests
// reach the parts through here instead of through RelayManager's public API
final _parts = Expando<RelayManagerParts>();

RelayManagerParts relayManagerParts(RelayManager manager) => _parts[manager]!;

void bindRelayManagerParts(RelayManager manager, RelayManagerParts parts) =>
    _parts[manager] = parts;
