import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:test/test.dart';

import 'package:dostr_mock_relay/dostr_mock_relay.dart';

const _clientPrivateKey =
    '7a8317f947fff0526749e9fe53f79def8eb0afd378c01058f37140cc8732fecc';

void main() {
  const eventSignerFactory = Bip340EventSignerFactory();

  late RelayManager relayManager;
  late RelayReqs relayReqs;
  late RelayPublishes relayPublishes;

  setUp(() {
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
  });

  tearDown(() => relayManager.closeAllTransports());

  Nip46EventSigner newSigner(List<String> relays) => Nip46EventSigner(
    connection: BunkerConnection(
      privateKey: _clientPrivateKey,
      remotePubkey: MockRemoteSigner.publicKey,
      relays: relays,
    ),
    relayReqs: relayReqs,
    relayPublishes: relayPublishes,
    eventSignerFactory: eventSignerFactory,
  );

  group('Nip46EventSigner', () {
    late MockRelay relay;
    late MockRemoteSigner remoteSigner;
    late Nip46EventSigner signer;

    setUp(() async {
      relay = MockRelay();
      await relay.start();
      remoteSigner = MockRemoteSigner([relay]);
      signer = newSigner([relay.url]);
    });

    tearDown(() async {
      await signer.dispose();
      await relay.stop();
    });

    test('canSign should return true', () {
      expect(signer.canSign(), isTrue);
    });

    test('sign should request remote signing and update event', () async {
      final event = Nip01Event(
        pubKey: MockRemoteSigner.publicKey,
        kind: 1,
        tags: [],
        content: 'Hello, world!',
      );

      final signedEvent = await signer.sign(event);

      expect(signedEvent.id, isNotNull);
      expect(signedEvent.sig, isNotNull);
    });

    test('sign should use event body returned by remote signer', () async {
      remoteSigner.signEventCreatedAtOffsetSeconds = 11;
      remoteSigner.signEventContentOverride = 'mutated by remote signer';

      final event = Nip01Event(
        pubKey: MockRemoteSigner.publicKey,
        kind: 1,
        tags: [
          ['t', 'test'],
        ],
        content: 'requested content',
        createdAt: 1234567890,
      );

      final signedEvent = await signer.sign(event);

      // Remote signer is allowed to modify the event before signing.
      expect(signedEvent.content, equals('mutated by remote signer'));
      expect(signedEvent.createdAt, equals(event.createdAt + 11));
      expect(signedEvent.hasValidId, isTrue);
      expect(await Bip340EventVerifier().verify(signedEvent), isTrue);
    });

    test('getPublicKey should throw when not cached', () {
      expect(() => signer.getPublicKey(), throwsException);
    });

    test('getPublicKeyAsync should fetch and cache public key', () async {
      final publicKey = await signer.getPublicKeyAsync();

      expect(publicKey, equals(MockRemoteSigner.publicKey));
      expect(signer.getPublicKey(), equals(publicKey));
    });

    test('connects with a bunker URL and signs through it', () async {
      final bunkers = Bunkers(
        relayReqs: relayReqs,
        relayPublishes: relayPublishes,
        eventSignerFactory: eventSignerFactory,
      );

      final bunkerConnection = await bunkers.connectWithBunkerUrl(
        'bunker://${MockRemoteSigner.publicKey}'
        '?relay=${relay.url}'
        '&secret=test-secret-123',
      );

      expect(bunkerConnection, isNotNull);
      expect(
        bunkerConnection!.remotePubkey,
        equals(MockRemoteSigner.publicKey),
      );
      expect(bunkerConnection.relays, contains(relay.url));

      final bunkerSigner = bunkers.createSigner(bunkerConnection);
      final signedTestEvent = await bunkerSigner.sign(
        Nip01Event(
          pubKey: MockRemoteSigner.publicKey,
          kind: 1,
          tags: [],
          content: 'Test event via bunker URL',
        ),
      );

      expect(signedTestEvent.id, isNotNull);
      expect(signedTestEvent.sig, isNotNull);

      await bunkerSigner.dispose();
    });

    test('decrypt should request remote decryption', () async {
      final keyPair = Bip340.generatePrivateKey();
      final localSigner = Bip340EventSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      const testMessage = 'Hello, this is a test message!';

      final encryptedMessage = await localSigner.encrypt(
        testMessage,
        MockRemoteSigner.publicKey,
      );
      final decryptedText = await signer.decrypt(
        encryptedMessage!,
        keyPair.publicKey,
      );

      expect(decryptedText, equals(testMessage));
    });

    test(
      'encrypt should request remote encryption and be verifiable',
      () async {
        const testMessage = 'Hello, this is a test message to encrypt!';
        final keyPair = Bip340.generatePrivateKey();
        final localSigner = Bip340EventSigner(
          privateKey: keyPair.privateKey,
          publicKey: keyPair.publicKey,
        );

        final encryptedMessage = await signer.encrypt(
          testMessage,
          keyPair.publicKey,
        );

        expect(encryptedMessage, isNotEmpty);
        expect(encryptedMessage, isNot(equals(testMessage)));
        expect(
          await localSigner.decrypt(
            encryptedMessage!,
            await signer.getPublicKeyAsync(),
          ),
          equals(testMessage),
        );
      },
    );

    test('decryptNip44 should request remote NIP-44 decryption', () async {
      final keyPair = Bip340.generatePrivateKey();
      final localSigner = Bip340EventSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      const testMessage = 'Hello, this is a NIP-44 test message!';

      final encryptedMessage = await localSigner.encryptNip44(
        plaintext: testMessage,
        recipientPubKey: MockRemoteSigner.publicKey,
      );
      final decryptedText = await signer.decryptNip44(
        ciphertext: encryptedMessage!,
        senderPubKey: keyPair.publicKey,
      );

      expect(decryptedText, equals(testMessage));
    });

    test(
      'encryptNip44 should request remote NIP-44 encryption and be verifiable',
      () async {
        const testMessage = 'Hello, this is a NIP-44 encryption test!';
        final keyPair = Bip340.generatePrivateKey();
        final localSigner = Bip340EventSigner(
          privateKey: keyPair.privateKey,
          publicKey: keyPair.publicKey,
        );

        final encryptedMessage = await signer.encryptNip44(
          plaintext: testMessage,
          recipientPubKey: keyPair.publicKey,
        );

        expect(encryptedMessage, isNotEmpty);
        expect(encryptedMessage, isNot(equals(testMessage)));
        expect(
          await localSigner.decryptNip44(
            ciphertext: encryptedMessage!,
            senderPubKey: await signer.getPublicKeyAsync(),
          ),
          equals(testMessage),
        );
      },
    );

    test('ping should return pong', () async {
      expect(await signer.ping(), equals('pong'));
    });
  });

  test('response is not held back by a slow transport relay', () async {
    final fastRelay = MockRelay();
    final slowRelay = MockRelay(answerEvents: false);
    await fastRelay.start();
    await slowRelay.start();
    addTearDown(fastRelay.stop);
    addTearDown(slowRelay.stop);
    MockRemoteSigner([fastRelay]);

    final signer = newSigner([fastRelay.url, slowRelay.url]);
    addTearDown(signer.dispose);

    final stopwatch = Stopwatch()..start();
    final response = await signer.ping();
    stopwatch.stop();

    expect(response, equals('pong'));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}
