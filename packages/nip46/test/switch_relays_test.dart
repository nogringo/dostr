import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip46/ndk_nip46.dart';
import 'package:test/test.dart';

import 'package:ndk_mock_relay/ndk_mock_relay.dart';

void main() {
  late MockRelay relayA;
  late MockRelay relayB;
  late MockRemoteSigner remoteSigner;
  late RelayManager relayManager;
  late Nip46EventSigner signer;

  int bunkerRequestsOn(MockRelay relay) => relay
      .received('EVENT')
      .where((message) => message[1]['kind'] == BunkerRequest.kKind)
      .length;

  setUp(() async {
    relayA = MockRelay();
    relayB = MockRelay();
    await relayA.start();
    await relayB.start();
    remoteSigner = MockRemoteSigner([relayA, relayB]);

    relayManager = RelayManager(
      nostrTransportFactory: WebSocketClientNostrTransportFactory(
        pingInterval: null,
      ),
    );
    signer = Nip46EventSigner(
      connection: BunkerConnection(
        privateKey:
            '7a8317f947fff0526749e9fe53f79def8eb0afd378c01058f37140cc8732fecc',
        remotePubkey: MockRemoteSigner.publicKey,
        relays: [relayA.url],
      ),
      relayReqs: RelayReqs(
        relayManager: relayManager,
        eventVerifier: Bip340EventVerifier(useIsolate: false),
      ),
      relayPublishes: RelayPublishes(relayManager: relayManager),
      eventSignerFactory: const Bip340EventSignerFactory(),
    );
  });

  tearDown(() async {
    await signer.dispose();
    await relayManager.closeAllTransports();
    await relayA.stop();
    await relayB.stop();
  });

  test('switches to the relays sent by the remote signer', () async {
    remoteSigner.switchRelaysResult = [relayB.url];

    final relays = await signer.switchRelays();

    expect(relays, equals([relayB.url]));
    expect(signer.connection.relays, equals([relayB.url]));

    final requestsOnA = bunkerRequestsOn(relayA);
    expect(await signer.ping(), equals('pong'));
    expect(bunkerRequestsOn(relayA), equals(requestsOnA));
    expect(bunkerRequestsOn(relayB), equals(1));
  });

  test('keeps the relays when the remote signer answers null', () async {
    expect(await signer.switchRelays(), isNull);
    expect(signer.connection.relays, equals([relayA.url]));
    expect(await signer.ping(), equals('pong'));
  });
}
