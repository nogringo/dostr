import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip46/ndk_nip46.dart';

/// `dart run example/ndk_nip46_example.dart 'bunker://<pubkey>?relay=wss://...&secret=...'`
Future<void> main(List<String> args) async {
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final bunkers = Bunkers(
    relayReqs: RelayReqs(
      relayManager: relayManager,
      eventVerifier: Bip340EventVerifier(),
    ),
    relayPublishes: RelayPublishes(relayManager: relayManager),
    eventSignerFactory: const Bip340EventSignerFactory(),
  );

  final connection = await bunkers.connectWithBunkerUrl(
    args.first,
    clientMetadata: const Nip46ClientMetadata(name: 'ndk_nip46 example'),
    authCallback: (url) => print('approve the connection at $url'),
  );
  if (connection != null) {
    final signer = bunkers.createSigner(connection);
    final pubkey = await signer.getPublicKeyAsync();
    final note = await signer.sign(
      Nip01Event(pubKey: pubkey, kind: 1, tags: [], content: 'hello'),
    );
    print(note.toJsonString());
    await signer.dispose();
  }

  await relayManager.closeAllTransports();
}
