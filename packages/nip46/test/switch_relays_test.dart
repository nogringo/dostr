import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:test/test.dart';

void main() {
  late MockRelay relayA;
  late MockRelay relayB;
  late MockRemoteSigner remoteSigner;
  late RelayManager relayManager;
  late BunkerConnection connection;
  late Nip46Signer signer;

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
      nostrTransportFactory: webSocketTransportFactory(pingInterval: null),
    );
    connection = BunkerConnection(
      privateKey:
          '7a8317f947fff0526749e9fe53f79def8eb0afd378c01058f37140cc8732fecc',
      remotePubkey: MockRemoteSigner.publicKey,
      relays: [relayA.url],
    );
    signer = Nip46Signer(
      connection: connection,
      publicKey: MockRemoteSigner.publicKey,
      relayReqs: RelayReqs(
        relayManager: relayManager,
        eventVerifier: Bip340EventVerifier(),
      ),
      relayPublishes: RelayPublishes(relayManager: relayManager),
      signerFactory: const Bip340SignerFactory(),
    );
  });

  tearDown(() async {
    await signer.dispose();
    await relayManager.dispose();
    await relayA.stop();
    await relayB.stop();
  });

  test('switches to the relays sent by the remote signer', () async {
    remoteSigner.switchRelaysResult = [relayB.url];

    final relays = await signer.switchRelays();

    expect(relays, equals([relayB.url]));
    expect(signer.connection.relays, equals([relayB.url]));
    expect(connection.relays, equals([relayA.url]));

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

  test('keeps the relays when none it is sent is a relay url', () async {
    remoteSigner.switchRelaysResult = ['https://relay.example.com'];

    expect(await signer.switchRelays(), isNull);
    expect(signer.connection.relays, equals([relayA.url]));
  });

  test('fails on an answer that is neither a list nor null', () async {
    for (final answer in ['ack', '{"relays": []}']) {
      remoteSigner.answers['switch_relays'] = {'result': answer};

      await expectLater(
        signer.switchRelays(),
        throwsA(isA<SignerRequestFailedException>()),
      );
    }
    expect(signer.connection.relays, equals([relayA.url]));
  });
}
