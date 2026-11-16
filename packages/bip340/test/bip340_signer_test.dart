import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:test/test.dart';

void main() {
  group('Bip340Signer', () {
    late Bip340Signer signer;
    late KeyPair keyPair;

    setUp(() {
      keyPair = Bip340.generatePrivateKey();
      signer = Bip340Signer(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
    });

    tearDown(() async {
      await signer.dispose();
    });

    group('pending requests (local signer)', () {
      test('pendingRequests returns empty list', () {
        expect(signer.pendingRequests, isEmpty);
      });

      test('pendingRequestsStream emits empty list', () async {
        final requests = await signer.pendingRequestsStream.first;
        expect(requests, isEmpty);
      });

      test('cancelRequest returns false (no pending requests)', () {
        final result = signer.cancelRequest('any-request-id');
        expect(result, isFalse);
      });

      test('dispose closes stream without error', () async {
        await signer.dispose();
        // Re-create signer for tearDown
        signer = Bip340Signer(
          privateKey: keyPair.privateKey,
          publicKey: keyPair.publicKey,
        );
      });
    });

    group('signing', () {
      test('sign returns valid signature', () async {
        final event = Nip01Event(
          pubkey: keyPair.publicKey,
          kind: 1,
          tags: [],
          content: 'Test content',
        );

        final signedEvent = await signer.sign(event);
        final verifier = Bip340EventVerifier();
        final isValid = await verifier.verify(signedEvent);

        expect(isValid, isTrue);
      });

      test('sign throws when no private key', () async {
        final readOnlySigner = Bip340Signer(
          privateKey: null,
          publicKey: keyPair.publicKey,
        );

        final event = Nip01Event(
          pubkey: keyPair.publicKey,
          kind: 1,
          tags: [],
          content: 'Test content',
        );

        expect(() => readOnlySigner.sign(event), throwsException);

        await readOnlySigner.dispose();
      });
    });

    group('canSign', () {
      test('returns true when private key is present', () {
        expect(signer.canSign, isTrue);
      });

      test('returns false when no private key', () {
        final readOnlySigner = Bip340Signer(
          privateKey: null,
          publicKey: keyPair.publicKey,
        );

        expect(readOnlySigner.canSign, isFalse);
      });
    });

    group('getPublicKey', () {
      test('returns the public key', () {
        expect(signer.getPublicKey(), equals(keyPair.publicKey));
      });
    });

    group('encryption/decryption', () {
      test('encrypt and decrypt NIP-04 roundtrip', () async {
        final otherKeyPair = Bip340.generatePrivateKey();
        final otherSigner = Bip340Signer(
          privateKey: otherKeyPair.privateKey,
          publicKey: otherKeyPair.publicKey,
        );

        const message = 'Hello, world!';

        final encrypted = await signer.encryptNip04(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
        expect(encrypted, isNot(equals(message)));

        final decrypted = await otherSigner.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: keyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await otherSigner.dispose();
      });

      test('encrypt and decrypt NIP-44 roundtrip', () async {
        final otherKeyPair = Bip340.generatePrivateKey();
        final otherSigner = Bip340Signer(
          privateKey: otherKeyPair.privateKey,
          publicKey: otherKeyPair.publicKey,
        );

        const message = 'Hello, NIP-44 world!';

        final encrypted = await signer.encryptNip44(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
        expect(encrypted, isNot(equals(message)));

        final decrypted = await otherSigner.decryptNip44(
          ciphertext: encrypted,
          senderPubkey: keyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await otherSigner.dispose();
      });

      test('NIP-44 keeps each peer apart across repeated messages', () async {
        final peers = [Bip340.generatePrivateKey(), Bip340.generatePrivateKey()]
            .map(
              (k) => Bip340Signer(
                privateKey: k.privateKey,
                publicKey: k.publicKey,
              ),
            )
            .toList();

        for (var round = 0; round < 3; round++) {
          for (final peer in peers) {
            final message = 'round $round to ${peer.publicKey}';
            final sent = await signer.encryptNip44(
              plaintext: message,
              recipientPubkey: peer.publicKey,
            );
            expect(
              await peer.decryptNip44(
                ciphertext: sent,
                senderPubkey: keyPair.publicKey,
              ),
              equals(message),
            );

            final reply = await peer.encryptNip44(
              plaintext: 'reply $message',
              recipientPubkey: keyPair.publicKey,
            );
            expect(
              await signer.decryptNip44(
                ciphertext: reply,
                senderPubkey: peer.publicKey,
              ),
              equals('reply $message'),
            );
          }
        }

        for (final peer in peers) {
          await peer.dispose();
        }
      });
    });
  });

  group('Bip340SignerFactory', () {
    late Bip340SignerFactory factory;

    setUp(() {
      factory = const Bip340SignerFactory();
    });

    group('generateKeyPair', () {
      test('generates valid keypair', () {
        final (privateKey, publicKey) = factory.generateKeyPair();

        expect(privateKey, isNotEmpty);
        expect(publicKey, isNotEmpty);
      });

      test('generated public key is the one of the private key', () {
        final (privateKey, publicKey) = factory.generateKeyPair();

        expect(publicKey, equals(Bip340.getPublicKey(privateKey)));
      });

      test('generates unique keypairs', () {
        final (privKey1, pubkey1) = factory.generateKeyPair();
        final (privKey2, pubkey2) = factory.generateKeyPair();

        expect(privKey1, isNot(equals(privKey2)));
        expect(pubkey1, isNot(equals(pubkey2)));
      });
    });

    group('create', () {
      test('derives the public key of the private key', () async {
        final keyPair = Bip340.generatePrivateKey();
        final signer = factory.create(keyPair.privateKey!);

        expect(signer.getPublicKey(), equals(keyPair.publicKey));
        expect(signer.canSign, isTrue);

        await signer.dispose();
      });

      test('signs valid events', () async {
        final keyPair = Bip340.generatePrivateKey();
        final signer = factory.create(keyPair.privateKey!);

        final event = Nip01Event(
          pubkey: signer.getPublicKey(),
          kind: 1,
          tags: [],
          content: 'Test with derived public key',
        );

        final signedEvent = await signer.sign(event);
        final verifier = Bip340EventVerifier();
        final isValid = await verifier.verify(signedEvent);

        expect(isValid, isTrue);

        await signer.dispose();
      });
    });

    group('readOnly', () {
      test('signs for the public key but cannot sign', () async {
        final keyPair = Bip340.generatePrivateKey();
        final signer = factory.readOnly(keyPair.publicKey);

        expect(signer.getPublicKey(), equals(keyPair.publicKey));
        expect(signer.canSign, isFalse);

        await signer.dispose();
      });
    });

    group('createWithNewKeyPair', () {
      test('creates signer with fresh keypair', () async {
        final signer = factory.createWithNewKeyPair();

        expect(signer.getPublicKey(), isNotEmpty);
        expect(signer.canSign, isTrue);

        await signer.dispose();
      });

      test('creates unique signers each time', () async {
        final signer1 = factory.createWithNewKeyPair();
        final signer2 = factory.createWithNewKeyPair();

        expect(signer1.getPublicKey(), isNot(equals(signer2.getPublicKey())));

        await signer1.dispose();
        await signer2.dispose();
      });

      test('created signer can sign valid events', () async {
        final signer = factory.createWithNewKeyPair();

        final event = Nip01Event(
          pubkey: signer.getPublicKey(),
          kind: 1,
          tags: [],
          content: 'Test with new keypair',
        );

        final signedEvent = await signer.sign(event);
        final verifier = Bip340EventVerifier();
        final isValid = await verifier.verify(signedEvent);

        expect(isValid, isTrue);

        await signer.dispose();
      });
    });

    group('factory is const', () {
      test('same instance when created with const', () {
        const factory1 = Bip340SignerFactory();
        const factory2 = Bip340SignerFactory();

        expect(identical(factory1, factory2), isTrue);
      });
    });
  });
}
