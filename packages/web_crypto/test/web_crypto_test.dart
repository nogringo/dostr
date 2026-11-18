@TestOn('browser')
library;

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('WebSigner', () {
    late WebSigner signer;
    late KeyPair keyPair;

    setUp(() {
      keyPair = Bip340.generateKeyPair();
      signer = WebSigner(keyPair.privateKey);
    });

    tearDown(() async {
      await signer.dispose();
    });

    test('publicKey is the public key', () {
      expect(signer.publicKey, equals(keyPair.publicKey));
    });

    test('rejects a private key that is not one', () {
      for (final invalid in [
        '',
        keyPair.privateKey.substring(2),
        '1z${keyPair.privateKey.substring(2)}',
        '00' * 32,
        'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
      ]) {
        expect(() => WebSigner(invalid), throwsFormatException);
        expect(
          () => const WebSignerFactory().create(invalid),
          throwsFormatException,
        );
      }
    });

    test('readOnly rejects a public key that is not NIP-01 hex', () {
      expect(
        () => WebSigner.readOnly(keyPair.publicKey.toUpperCase()),
        throwsFormatException,
      );
    });

    test('an invalid recipient public key fails the request', () async {
      await expectLater(
        signer.encryptNip44(
          plaintext: 'hello',
          recipientPubkey: '1z${keyPair.publicKey.substring(2)}',
        ),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('canSign returns true when private key is present', () {
      expect(signer.canSign, isTrue);
    });

    test('canSign returns false when no private key', () {
      final readOnlySigner = WebSigner.readOnly(keyPair.publicKey);
      expect(readOnlySigner.canSign, isFalse);
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
      const webVerifier = WebEventVerifier();
      final isValidWeb = await webVerifier.verify(signedEvent);
      expect(isValidWeb, isTrue);
    });

    test('sign throws when no private key', () async {
      final readOnlySigner = WebSigner.readOnly(keyPair.publicKey);

      final event = Nip01Event(
        pubkey: keyPair.publicKey,
        kind: 1,
        tags: [],
        content: 'Test content',
      );

      expect(() => readOnlySigner.sign(event), throwsStateError);
      await readOnlySigner.dispose();
    });

    test('sign throws for an event of another pubkey', () async {
      final event = Nip01Event(
        pubkey: Bip340.generateKeyPair().publicKey,
        kind: 1,
        tags: [],
        content: 'Test content',
      );

      expect(() => signer.sign(event), throwsArgumentError);
    });

    test('a ciphertext that does not decrypt fails the request', () async {
      expect(
        () => signer.decryptNip44(
          ciphertext: 'not a nip44 payload',
          senderPubkey: keyPair.publicKey,
        ),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    group('NIP-04 interop with Bip340Signer', () {
      late KeyPair otherKeyPair;

      setUp(() {
        otherKeyPair = Bip340.generateKeyPair();
      });

      test('encrypt with WebSigner, decrypt with Bip340Signer', () async {
        final dartSigner = Bip340Signer(otherKeyPair.privateKey);

        const message = 'Hello, NIP-04 from web!';
        final encrypted = await signer.encryptNip04(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
        expect(encrypted, isNot(equals(message)));

        final decrypted = await dartSigner.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: keyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await dartSigner.dispose();
      });

      test('encrypt with Bip340Signer, decrypt with WebSigner', () async {
        final dartSigner = Bip340Signer(otherKeyPair.privateKey);

        const message = 'Hello from Dart NIP-04!';
        final encrypted = await dartSigner.encryptNip04(
          plaintext: message,
          recipientPubkey: keyPair.publicKey,
        );

        final decrypted = await signer.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: otherKeyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await dartSigner.dispose();
      });
    });

    group('NIP-44 interop with Bip340Signer', () {
      late KeyPair otherKeyPair;

      setUp(() {
        otherKeyPair = Bip340.generateKeyPair();
      });

      test('encrypt with WebSigner, decrypt with Bip340Signer', () async {
        final dartSigner = Bip340Signer(otherKeyPair.privateKey);

        const message = 'Hello, NIP-44 from web!';
        final encrypted = await signer.encryptNip44(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
        expect(encrypted, isNot(equals(message)));

        final decrypted = await dartSigner.decryptNip44(
          ciphertext: encrypted,
          senderPubkey: keyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await dartSigner.dispose();
      });

      test('encrypt with Bip340Signer, decrypt with WebSigner', () async {
        final dartSigner = Bip340Signer(otherKeyPair.privateKey);

        const message = 'Hello from Dart NIP-44!';
        final encrypted = await dartSigner.encryptNip44(
          plaintext: message,
          recipientPubkey: keyPair.publicKey,
        );

        final decrypted = await signer.decryptNip44(
          ciphertext: encrypted,
          senderPubkey: otherKeyPair.publicKey,
        );
        expect(decrypted, equals(message));

        await dartSigner.dispose();
      });

      for (final length in [65535, 65536, 100000]) {
        test('a message of $length bytes goes both ways', () async {
          final dartSigner = Bip340Signer(otherKeyPair.privateKey);
          final message = 'a' * length;

          final fromWeb = await signer.encryptNip44(
            plaintext: message,
            recipientPubkey: otherKeyPair.publicKey,
          );
          expect(
            await dartSigner.decryptNip44(
              ciphertext: fromWeb,
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
              ciphertext: fromDart,
              senderPubkey: otherKeyPair.publicKey,
            ),
            message,
          );

          await dartSigner.dispose();
        });
      }

      test('keeps each peer apart across repeated messages', () async {
        final peers = [
          otherKeyPair,
          Bip340.generateKeyPair(),
        ].map((k) => Bip340Signer(k.privateKey)).toList();

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
              message,
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
              'reply $message',
            );
          }
        }

        for (final peer in peers) {
          await peer.dispose();
        }
      });
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

      test('dispose completes without error', () async {
        await signer.dispose();
      });
    });
  });

  group('WebSignerFactory', () {
    const factory = WebSignerFactory();

    test('create derives the public key as Bip340 does', () {
      final keyPair = Bip340.generateKeyPair();
      final signer = factory.create(keyPair.privateKey);
      expect(signer.publicKey, equals(keyPair.publicKey));
      expect(signer.canSign, isTrue);
    });

    test('readOnly cannot sign', () {
      final keyPair = Bip340.generateKeyPair();
      final signer = factory.readOnly(keyPair.publicKey);
      expect(signer.publicKey, equals(keyPair.publicKey));
      expect(signer.canSign, isFalse);
    });

    test('generateKeyPair returns a matching key pair', () {
      final (:privateKey, :publicKey) = factory.generateKeyPair();
      expect(privateKey, hasLength(64));
      expect(publicKey, equals(Bip340.getPublicKey(privateKey)));
    });
  });
}
