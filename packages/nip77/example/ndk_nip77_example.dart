import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip77/ndk_nip77.dart';

Future<void> main() async {
  final relays = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
    bootstrapRelays: [],
  );

  // nothing is stored yet, so every matching event on the relay is needed
  final nip77 = Nip77(
    relayManager: relays,
    loadEventIds: (filter) async => [],
    loadEvent: (id) async => null,
  );

  final response = nip77.reconcile(
    relayUrl: 'wss://relay.example.com',
    filter: Filter(kinds: [0], limit: 100),
  );
  final result = await response.future;
  print('need ${result.needIds.length}, have ${result.haveIds.length}');

  await relays.closeAllTransports();
}
