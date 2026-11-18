@TestOn('browser')
library;

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';
import 'package:test/test.dart';

void _report(String label, int count, int ms) {
  final perOp = count > 0 ? (ms / count).toStringAsFixed(2) : '0';
  print('[$label] $count ops in ${ms}ms ($perOp ms/op)');
}

void main() {
  group('WebSigner benchmark', () {
    late KeyPair keyPair;
    late Nip01Event event;

    setUpAll(() {
      keyPair = Bip340.generateKeyPair();
      event = Nip01Event(
        pubkey: keyPair.publicKey,
        kind: 1,
        tags: [],
        content: 'Benchmark event content',
      );
    });

    test('benchmark sign', () async {
      const count = 10;

      final webSigner = WebSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      final dartSigner = Bip340Signer(keyPair.privateKey);

      // Warmup
      for (var i = 0; i < 3; i++) {
        await webSigner.sign(event);
      }
      for (var i = 0; i < 3; i++) {
        await dartSigner.sign(event);
      }

      // Web
      var sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await webSigner.sign(event);
      }
      sw.stop();
      _report('WebSigner.sign', count, sw.elapsedMilliseconds);

      // Dart
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartSigner.sign(event);
      }
      sw.stop();
      _report('Bip340Signer.sign', count, sw.elapsedMilliseconds);

      await webSigner.dispose();
      await dartSigner.dispose();
    });

    test('benchmark verify', () async {
      const count = 50;

      final signer = Bip340Signer(keyPair.privateKey);
      final signedEvent = await signer.sign(event);
      await signer.dispose();

      final webVerifier = WebEventVerifier();
      final dartVerifier = Bip340EventVerifier();

      // Warmup
      for (var i = 0; i < 3; i++) {
        await webVerifier.verify(signedEvent);
      }
      for (var i = 0; i < 3; i++) {
        await dartVerifier.verify(signedEvent);
      }

      // Web
      var sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await webVerifier.verify(signedEvent);
      }
      sw.stop();
      _report('WebEventVerifier.verify', count, sw.elapsedMilliseconds);

      // Dart
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartVerifier.verify(signedEvent);
      }
      sw.stop();
      _report('Bip340EventVerifier.verify', count, sw.elapsedMilliseconds);
    });

    test('benchmark nip04 encrypt', () async {
      const count = 10;
      const message = 'Hello, NIP-04 benchmark!';
      final otherKeyPair = Bip340.generateKeyPair();

      final webSigner = WebSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      final dartSigner = Bip340Signer(keyPair.privateKey);

      // Warmup
      for (var i = 0; i < 3; i++) {
        await webSigner.encryptNip04(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }
      for (var i = 0; i < 3; i++) {
        await dartSigner.encryptNip04(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }

      // Web
      var sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await webSigner.encryptNip04(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }
      sw.stop();
      _report('WebSigner.nip04Encrypt', count, sw.elapsedMilliseconds);

      // Dart
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartSigner.encryptNip04(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }
      sw.stop();
      _report('Bip340Signer.nip04Encrypt', count, sw.elapsedMilliseconds);

      await webSigner.dispose();
      await dartSigner.dispose();
    });

    test('benchmark nip44 encrypt', () async {
      const count = 10;
      const message = 'Hello, NIP-44 benchmark!';
      final otherKeyPair = Bip340.generateKeyPair();

      final webSigner = WebSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      final dartSigner = Bip340Signer(keyPair.privateKey);

      // Warmup
      for (var i = 0; i < 3; i++) {
        await webSigner.encryptNip44(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }
      for (var i = 0; i < 3; i++) {
        await dartSigner.encryptNip44(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }

      // Web
      var sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await webSigner.encryptNip44(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }
      sw.stop();
      _report('WebSigner.nip44Encrypt', count, sw.elapsedMilliseconds);

      // Dart
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartSigner.encryptNip44(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }
      sw.stop();
      _report('Bip340Signer.nip44Encrypt', count, sw.elapsedMilliseconds);

      await webSigner.dispose();
      await dartSigner.dispose();
    });

    test('benchmark nip04 decrypt', () async {
      const count = 10;
      const message = 'Hello, NIP-04 decrypt benchmark!';
      final otherKeyPair = Bip340.generateKeyPair();

      final webSigner = WebSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      final dartSigner = Bip340Signer(otherKeyPair.privateKey);

      final encrypted = await webSigner.encryptNip04(
        plaintext: message,
        recipientPubkey: otherKeyPair.publicKey,
      );

      // Warmup
      for (var i = 0; i < 3; i++) {
        await dartSigner.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: keyPair.publicKey,
        );
      }
      for (var i = 0; i < 3; i++) {
        await webSigner.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: otherKeyPair.publicKey,
        );
      }

      // Dart decrypt
      var sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartSigner.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: keyPair.publicKey,
        );
      }
      sw.stop();
      _report('Bip340Signer.nip04Decrypt', count, sw.elapsedMilliseconds);

      // Web decrypt
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await webSigner.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: otherKeyPair.publicKey,
        );
      }
      sw.stop();
      _report('WebSigner.nip04Decrypt', count, sw.elapsedMilliseconds);

      await webSigner.dispose();
      await dartSigner.dispose();
    });

    test('benchmark nip44 decrypt', () async {
      const count = 10;
      const message = 'Hello, NIP-44 decrypt benchmark!';
      final otherKeyPair = Bip340.generateKeyPair();

      final webSigner = WebSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      final dartSigner = Bip340Signer(otherKeyPair.privateKey);

      final encrypted = await webSigner.encryptNip44(
        plaintext: message,
        recipientPubkey: otherKeyPair.publicKey,
      );

      // Warmup
      for (var i = 0; i < 3; i++) {
        await dartSigner.decryptNip44(
          ciphertext: encrypted,
          senderPubkey: keyPair.publicKey,
        );
      }
      for (var i = 0; i < 3; i++) {
        await webSigner.decryptNip44(
          ciphertext: encrypted,
          senderPubkey: otherKeyPair.publicKey,
        );
      }

      // Dart decrypt
      var sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartSigner.decryptNip44(
          ciphertext: encrypted,
          senderPubkey: keyPair.publicKey,
        );
      }
      sw.stop();
      _report('Bip340Signer.nip44Decrypt', count, sw.elapsedMilliseconds);

      // Web decrypt
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await webSigner.decryptNip44(
          ciphertext: encrypted,
          senderPubkey: otherKeyPair.publicKey,
        );
      }
      sw.stop();
      _report('WebSigner.nip44Decrypt', count, sw.elapsedMilliseconds);

      await webSigner.dispose();
      await dartSigner.dispose();
    });
  });
}
