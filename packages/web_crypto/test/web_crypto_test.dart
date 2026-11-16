@TestOn('browser')
library;

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('WebSigner', () {
    late WebSigner signer;
    late KeyPair keyPair;

    setUp(() {
      keyPair = Bip340.generatePrivateKey();
      signer = WebSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
    });

    tearDown(() async {
      await signer.dispose();
    });

    test('getPublicKey returns the public key', () {
      expect(signer.getPublicKey(), equals(keyPair.publicKey));
    });

    test('canSign returns true when private key is present', () {
      expect(signer.canSign(), isTrue);
    });

    test('canSign returns false when no private key', () {
      final readOnlySigner = WebSigner(
        privateKey: null,
        publicKey: keyPair.publicKey,
      );
      expect(readOnlySigner.canSign(), isFalse);
    });

    test('sign returns valid signature', () async {
      final event = Nip01Event(
        pubkey: keyPair.publicKey,
        kind: 1,
        tags: [],
        content: 'Test content',
      );

      final signedEvent = await signer.sign(event);
      expect(signedEvent.sig, isNotNull);
      expect(signedEvent.sig, isNotEmpty);

      // Verify with pure Dart verifier
      final dartVerifier = Bip340EventVerifier();
      final isValidDart = await dartVerifier.verify(signedEvent);
      expect(isValidDart, isTrue);

      // Verify with web verifier
      final webVerifier = WebEventVerifier();
      final isValidWeb = await webVerifier.verify(signedEvent);
      expect(isValidWeb, isTrue);
    });

    test('sign throws when no private key', () async {
      final readOnlySigner = WebSigner(
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

    group('NIP-04 interop with Bip340Signer', () {
      late KeyPair otherKeyPair;

      setUp(() {
        otherKeyPair = Bip340.generatePrivateKey();
      });

      test('encrypt with WebSigner, decrypt with Bip340Signer', () async {
        final dartSigner = Bip340Signer(
          privateKey: otherKeyPair.privateKey,
          publicKey: otherKeyPair.publicKey,
        );

        const message = 'Hello, NIP-04 from web!';
        final encrypted = await signer.encrypt(message, otherKeyPair.publicKey);
        expect(encrypted, isNotNull);
        expect(encrypted, isNot(equals(message)));

        final decrypted = await dartSigner.decrypt(
          encrypted!,
          keyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await dartSigner.dispose();
      });

      test('encrypt with Bip340Signer, decrypt with WebSigner', () async {
        final dartSigner = Bip340Signer(
          privateKey: otherKeyPair.privateKey,
          publicKey: otherKeyPair.publicKey,
        );

        const message = 'Hello from Dart NIP-04!';
        final encrypted = await dartSigner.encrypt(message, keyPair.publicKey);
        expect(encrypted, isNotNull);

        final decrypted = await signer.decrypt(
          encrypted!,
          otherKeyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await dartSigner.dispose();
      });
    });

    group('NIP-44 interop with Bip340Signer', () {
      late KeyPair otherKeyPair;

      setUp(() {
        otherKeyPair = Bip340.generatePrivateKey();
      });

      test('encrypt with WebSigner, decrypt with Bip340Signer', () async {
        final dartSigner = Bip340Signer(
          privateKey: otherKeyPair.privateKey,
          publicKey: otherKeyPair.publicKey,
        );

        const message = 'Hello, NIP-44 from web!';
        final encrypted = await signer.encryptNip44(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
        expect(encrypted, isNotNull);
        expect(encrypted, isNot(equals(message)));

        final decrypted = await dartSigner.decryptNip44(
          ciphertext: encrypted!,
          senderPubkey: keyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await dartSigner.dispose();
      });

      test('encrypt with Bip340Signer, decrypt with WebSigner', () async {
        final dartSigner = Bip340Signer(
          privateKey: otherKeyPair.privateKey,
          publicKey: otherKeyPair.publicKey,
        );

        const message = 'Hello from Dart NIP-44!';
        final encrypted = await dartSigner.encryptNip44(
          plaintext: message,
          recipientPubkey: keyPair.publicKey,
        );
        expect(encrypted, isNotNull);

        final decrypted = await signer.decryptNip44(
          ciphertext: encrypted!,
          senderPubkey: otherKeyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await dartSigner.dispose();
      });

      for (final length in [65535, 65536, 100000]) {
        test('a message of $length bytes goes both ways', () async {
          final dartSigner = Bip340Signer(
            privateKey: otherKeyPair.privateKey,
            publicKey: otherKeyPair.publicKey,
          );
          final message = 'a' * length;

          final fromWeb = await signer.encryptNip44(
            plaintext: message,
            recipientPubkey: otherKeyPair.publicKey,
          );
          expect(
            await dartSigner.decryptNip44(
              ciphertext: fromWeb!,
              senderPubkey: keyPair.publicKey,
            ),
            message,
          );

          final fromDart = await dartSigner.encryptNip44(
            plaintext: message,
            recipientPubkey: keyPair.publicKey,
          );
          expect(
            await signer.decryptNip44(
              ciphertext: fromDart!,
              senderPubkey: otherKeyPair.publicKey,
            ),
            message,
          );

          await dartSigner.dispose();
        });
      }
    });

    group('pending requests (local signer)', () {
      test('pendingRequests returns empty list', () {
        expect(signer.pendingRequests, isEmpty);
      });

      test('pendingRequestsStream emits empty list', () async {
        final requests = await signer.pendingRequestsStream.first;
        expect(requests, isEmpty);
      });

      test('cancelRequest returns false', () {
        expect(signer.cancelRequest('any-id'), isFalse);
      });

      test('dispose closes stream without error', () async {
        await signer.dispose();
        // Recreate for tearDown
        signer = WebSigner(
          privateKey: keyPair.privateKey,
          publicKey: keyPair.publicKey,
        );
      });
    });
  });

  group('WebSignerFactory', () {
    const factory = WebSignerFactory();

    test('derivePublicKey matches Bip340', () {
      final keyPair = Bip340.generatePrivateKey();
      expect(
        factory.derivePublicKey(keyPair.privateKey!),
        equals(keyPair.publicKey),
      );
    });

    test('generateKeyPair returns a matching key pair', () {
      final (privateKey, publicKey) = factory.generateKeyPair();
      expect(privateKey, hasLength(64));
      expect(publicKey, equals(Bip340.getPublicKey(privateKey)));
    });
  });
}
