import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';
import 'package:test/test.dart';

const _clientPrivateKey =
    '7a8317f947fff0526749e9fe53f79def8eb0afd378c01058f37140cc8732fecc';

void main() {
  const signerFactory = Bip340SignerFactory();

  late RelayManager relayManager;
  late RelayReqs relayReqs;
  late RelayPublishes relayPublishes;
  late MockRelay relay;

  setUp(() async {
    relayManager = RelayManager(
      nostrTransportFactory: WebSocketClientNostrTransportFactory(
        pingInterval: null,
      ),
    );
    relayReqs = RelayReqs(
      relayManager: relayManager,
      eventVerifier: Bip340EventVerifier(),
    );
    relayPublishes = RelayPublishes(relayManager: relayManager);
    relay = MockRelay();
    await relay.start();
    MockRemoteSigner([relay]);
  });

  tearDown(() async {
    await relayManager.closeAllTransports();
    await relay.stop();
  });

  runSignerTestSuite(
    name: 'Nip46Signer',
    createSigner: () => Nip46Signer(
      connection: BunkerConnection(
        privateKey: _clientPrivateKey,
        remotePubkey: MockRemoteSigner.publicKey,
        relays: [relay.url],
      ),
      publicKey: MockRemoteSigner.publicKey,
      relayReqs: relayReqs,
      relayPublishes: relayPublishes,
      signerFactory: signerFactory,
    ),
    createPeer: signerFactory.createWithNewKeyPair,
    verifier: Bip340EventVerifier(),
    interactive: true,
  );
}
