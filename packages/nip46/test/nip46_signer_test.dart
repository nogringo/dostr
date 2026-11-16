import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:test/test.dart';

const _clientPrivateKey =
    '7a8317f947fff0526749e9fe53f79def8eb0afd378c01058f37140cc8732fecc';

void main() {
  const signerFactory = Bip340SignerFactory();

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

  BunkerConnection connectionTo(List<RelayUrl> relays) => BunkerConnection(
    privateKey: _clientPrivateKey,
    remotePubkey: MockRemoteSigner.publicKey,
    relays: relays,
  );

  Nip46Signer newSigner(
    List<RelayUrl> relays, {
    String publicKey = MockRemoteSigner.publicKey,
  }) => Nip46Signer(
    connection: connectionTo(relays),
    publicKey: publicKey,
    relayReqs: relayReqs,
    relayPublishes: relayPublishes,
    signerFactory: signerFactory,
  );

  group('Nip46Signer', () {
    late MockRelay relay;
    late MockRemoteSigner remoteSigner;
    late Nip46Signer signer;

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
      expect(signer.canSign, isTrue);
    });

    test('sign should request remote signing and update event', () async {
      final event = Nip01Event(
        pubkey: MockRemoteSigner.publicKey,
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
        pubkey: MockRemoteSigner.publicKey,
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

    test('sign throws for an event of another pubkey', () async {
      final event = Nip01Event(
        pubkey: Bip340.generatePrivateKey().publicKey,
        kind: 1,
        content: 'not mine',
      );

      await expectLater(signer.sign(event), throwsArgumentError);
      expect(relay.received('EVENT'), isEmpty);
    });

    test('sign fails when the bunker signs as another pubkey', () async {
      final otherUser = Bip340.generatePrivateKey().publicKey;
      final wrongSigner = newSigner([relay.url], publicKey: otherUser);
      addTearDown(wrongSigner.dispose);

      await expectLater(
        wrongSigner.sign(
          Nip01Event(pubkey: otherUser, kind: 1, content: 'hello'),
        ),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('a signature waits as a PendingSignRequest', () async {
      final event = Nip01Event(
        pubkey: MockRemoteSigner.publicKey,
        kind: 1,
        content: 'pending',
      );

      final signing = signer.sign(event);
      final pending = signer.pendingRequests.single;

      expect(pending, isA<PendingSignRequest>());
      expect((pending as PendingSignRequest).event, same(event));
      expect(pending.signerPubkey, MockRemoteSigner.publicKey);
      await signing;
      expect(signer.pendingRequests, isEmpty);
    });

    test('a ping does not wait for the user', () async {
      final pinging = signer.ping();

      expect(signer.pendingRequests, isEmpty);
      expect(await pinging, 'pong');
    });

    test('connect asks the bunker for the user pubkey', () async {
      final connected = await Nip46Signer.connect(
        connection: connectionTo([relay.url]),
        relayReqs: relayReqs,
        relayPublishes: relayPublishes,
        signerFactory: signerFactory,
      );
      addTearDown(connected.dispose);

      expect(connected.publicKey, MockRemoteSigner.publicKey);
    });

    test('connects with a bunker URL and signs through it', () async {
      final bunkers = Bunkers(
        relayReqs: relayReqs,
        relayPublishes: relayPublishes,
        signerFactory: signerFactory,
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

      final bunkerSigner = await bunkers.createSigner(bunkerConnection);
      expect(bunkerSigner.publicKey, MockRemoteSigner.publicKey);
      final signedTestEvent = await bunkerSigner.sign(
        Nip01Event(
          pubkey: MockRemoteSigner.publicKey,
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
      final localSigner = Bip340Signer(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      const testMessage = 'Hello, this is a test message!';

      final encryptedMessage = await localSigner.encryptNip04(
        plaintext: testMessage,
        recipientPubkey: MockRemoteSigner.publicKey,
      );
      final decryptedText = await signer.decryptNip04(
        ciphertext: encryptedMessage,
        senderPubkey: keyPair.publicKey,
      );

      expect(decryptedText, equals(testMessage));
    });

    test(
      'encrypt should request remote encryption and be verifiable',
      () async {
        const testMessage = 'Hello, this is a test message to encrypt!';
        final keyPair = Bip340.generatePrivateKey();
        final localSigner = Bip340Signer(
          privateKey: keyPair.privateKey,
          publicKey: keyPair.publicKey,
        );

        final encryptedMessage = await signer.encryptNip04(
          plaintext: testMessage,
          recipientPubkey: keyPair.publicKey,
        );

        expect(encryptedMessage, isNotEmpty);
        expect(encryptedMessage, isNot(equals(testMessage)));
        expect(
          await localSigner.decryptNip04(
            ciphertext: encryptedMessage,
            senderPubkey: signer.publicKey,
          ),
          equals(testMessage),
        );
      },
    );

    test('decryptNip44 should request remote NIP-44 decryption', () async {
      final keyPair = Bip340.generatePrivateKey();
      final localSigner = Bip340Signer(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      const testMessage = 'Hello, this is a NIP-44 test message!';

      final encryptedMessage = await localSigner.encryptNip44(
        plaintext: testMessage,
        recipientPubkey: MockRemoteSigner.publicKey,
      );
      final decryptedText = await signer.decryptNip44(
        ciphertext: encryptedMessage,
        senderPubkey: keyPair.publicKey,
      );

      expect(decryptedText, equals(testMessage));
    });

    test(
      'encryptNip44 should request remote NIP-44 encryption and be verifiable',
      () async {
        const testMessage = 'Hello, this is a NIP-44 encryption test!';
        final keyPair = Bip340.generatePrivateKey();
        final localSigner = Bip340Signer(
          privateKey: keyPair.privateKey,
          publicKey: keyPair.publicKey,
        );

        final encryptedMessage = await signer.encryptNip44(
          plaintext: testMessage,
          recipientPubkey: keyPair.publicKey,
        );

        expect(encryptedMessage, isNotEmpty);
        expect(encryptedMessage, isNot(equals(testMessage)));
        expect(
          await localSigner.decryptNip44(
            ciphertext: encryptedMessage,
            senderPubkey: signer.publicKey,
          ),
          equals(testMessage),
        );
      },
    );

    test('ping should return pong', () async {
      expect(await signer.ping(), equals('pong'));
    });
  });

  test('connect fails when the bunker sends no pubkey in time', () async {
    final silentRelay = MockRelay();
    await silentRelay.start();
    addTearDown(silentRelay.stop);

    await expectLater(
      Nip46Signer.connect(
        connection: connectionTo([silentRelay.url]),
        relayReqs: relayReqs,
        relayPublishes: relayPublishes,
        signerFactory: signerFactory,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<SignerRequestFailedException>()),
    );
  });

  group('a request that waits for its turn', () {
    late MockRelay silentRelay;
    late Nip46Signer signer;

    Nip01Event note(String content) => Nip01Event(
      pubkey: MockRemoteSigner.publicKey,
      kind: 1,
      content: content,
    );

    setUp(() async {
      silentRelay = MockRelay();
      await silentRelay.start();
      signer = Nip46Signer(
        connection: connectionTo([silentRelay.url]),
        publicKey: MockRemoteSigner.publicKey,
        relayReqs: relayReqs,
        relayPublishes: relayPublishes,
        signerFactory: signerFactory,
        maxConcurrentRequests: 1,
      );
    });

    tearDown(() => silentRelay.stop());

    test('fails at once when cancelRequest drops it', () async {
      addTearDown(signer.dispose);
      final first = signer.sign(note('first'));
      final second = signer.sign(note('second'));
      final [firstId, secondId] = [
        for (final request in signer.pendingRequests) request.id,
      ];

      expect(signer.cancelRequest(secondId), isTrue);
      await expectLater(
        second,
        throwsA(isA<SignerRequestCancelledException>()),
      );
      expect(signer.cancelRequest(firstId), isTrue);
      await expectLater(first, throwsA(isA<SignerRequestCancelledException>()));
    });

    test('fails when the signer is disposed', () async {
      signer.sign(note('first')).ignore();
      final second = expectLater(
        signer.sign(note('second')),
        throwsA(isA<SignerRequestFailedException>()),
      );

      await signer.dispose();

      await second;
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
