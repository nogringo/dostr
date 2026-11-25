import 'package:dostr_core/dostr_core.dart';

import 'relay_host_filter.dart';

/// Whether the device reaches the internet, read from [connectivity], the
/// `RelayManager.relayConnectivityChanges` of dostr_core.
///
/// True once a connection to a public relay is open, false once every
/// connection to one failed or dropped. Connections that are still opening
/// tell nothing, and neither does a list without public relays: dostr_core
/// closes and forgets idle connections, so having none says nothing about
/// the network.
Stream<bool> publicRelayReachability(
  Stream<List<RelayConnectivity>> connectivity,
) => connectivity
    .map(
      (connections) => [
        for (final connection in connections)
          if (!connection.isConnecting && isPublicRelayHost(connection.key.url))
            connection.isConnected,
      ],
    )
    .where((settled) => settled.isNotEmpty)
    .map((settled) => settled.contains(true))
    .distinct();
