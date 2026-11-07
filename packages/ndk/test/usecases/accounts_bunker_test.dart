import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

void main() {
  final eventSignerFactory = Bip340EventSignerFactory();

  late MockRelay mockRelay;
  late Ndk ndk;
  late Accounts accounts;

  setUp(() async {
    mockRelay = MockRelay(name: 'accounts-bunker-relay');
    MockRemoteSigner([mockRelay]);
    await mockRelay.start();

    ndk = Ndk(
      NdkConfig(
        cache: MemCacheManager(),
        eventVerifier: Bip340EventVerifier(),
        bootstrapRelays: [mockRelay.url],
      ),
    );
    await ndk.bootstrapRelaysConnected;
    accounts = Accounts(eventSignerFactory);
  });

  tearDown(() async {
    for (final account in accounts.accounts.values) {
      await account.signer.dispose();
    }
    await ndk.destroy();
    await mockRelay.stop();
  });

  Future<void> expectSignsThroughBunker(String content) async {
    expect(accounts.isLoggedIn, isTrue);
    expect(accounts.getPublicKey(), equals(MockRemoteSigner.publicKey));

    final signedTestEvent = await accounts.sign(
      Nip01Event(
        pubKey: accounts.getPublicKey()!,
        kind: 1,
        tags: [],
        content: content,
      ),
    );

    expect(signedTestEvent.id, isNotNull);
    expect(signedTestEvent.sig, isNotNull);
  }

  test('loginWithBunkerUrl should set up account correctly', () async {
    final connection = await accounts.loginWithBunkerUrl(
      bunkerUrl:
          'bunker://${MockRemoteSigner.publicKey}'
          '?relay=${mockRelay.url}'
          '&secret=bunker-url-test-secret',
      bunkers: ndk.bunkers,
    );

    expect(connection, isNotNull);
    expect(connection!.remotePubkey, equals(MockRemoteSigner.publicKey));
    expect(connection.relays, contains(mockRelay.url));
    await expectSignsThroughBunker('Test event via loginWithBunkerUrl');
  });

  test('loginWithBunkerConnection should set up account correctly', () async {
    await accounts.loginWithBunkerConnection(
      connection: BunkerConnection(
        privateKey:
            "7a8317f947fff0526749e9fe53f79def8eb0afd378c01058f37140cc8732fecc",
        remotePubkey: MockRemoteSigner.publicKey,
        relays: [mockRelay.url],
      ),
      bunkers: ndk.bunkers,
    );

    await expectSignsThroughBunker('Test event via loginWithBunkerConnection');
  });
}
