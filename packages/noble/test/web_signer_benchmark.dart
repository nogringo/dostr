@TestOn('browser')
library;

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_noble/dostr_noble.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

void _report(String label, int count, Duration elapsed) {
  final ms = elapsed.inMicroseconds / 1000;
  final perOp = (ms / count).toStringAsFixed(3);
  print('[$label] $count ops in ${ms.toStringAsFixed(1)}ms ($perOp ms/op)');
}

List<(String, NostrSigner)> _signers(String privateKey) => [
  ('WebSigner', WebSigner(privateKey)),
  ('Bip340Signer', Bip340Signer(privateKey)),
];

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

      final webSigner = WebSigner(keyPair.privateKey);
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
      _report('WebSigner.sign', count, sw.elapsed);

      // Dart
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartSigner.sign(event);
      }
      sw.stop();
      _report('Bip340Signer.sign', count, sw.elapsed);

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
      _report('WebEventVerifier.verify', count, sw.elapsed);

      // Dart
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartVerifier.verify(signedEvent);
      }
      sw.stop();
      _report('Bip340EventVerifier.verify', count, sw.elapsed);
    });

    test('benchmark nip04 encrypt', () async {
      const count = 10;
      const message = 'Hello, NIP-04 benchmark!';
      final otherKeyPair = Bip340.generateKeyPair();

      final webSigner = WebSigner(keyPair.privateKey);
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
      _report('WebSigner.nip04Encrypt', count, sw.elapsed);

      // Dart
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await dartSigner.encryptNip04(
          plaintext: message,
          recipientPubkey: otherKeyPair.publicKey,
        );
      }
      sw.stop();
      _report('Bip340Signer.nip04Encrypt', count, sw.elapsed);

      await webSigner.dispose();
      await dartSigner.dispose();
    });

    test('benchmark nip44 encrypt', () async {
      const count = 10;
      const message = 'Hello, NIP-44 benchmark!';
      final peers = [
        for (var i = 0; i < count + 3; i++) Bip340.generateKeyPair().publicKey,
      ];

      for (final (name, signer) in _signers(keyPair.privateKey)) {
        Future<String> encrypt(String peer) =>
            signer.encryptNip44(plaintext: message, recipientPubkey: peer);

        for (final peer in peers.take(3)) {
          await encrypt(peer);
        }

        // a new peer runs the key agreement, as each gift wrap does
        var sw = Stopwatch()..start();
        for (final peer in peers.skip(3)) {
          await encrypt(peer);
        }
        _report('$name.nip44Encrypt, new peer', count, sw.elapsed);

        sw = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          await encrypt(peers.last);
        }
        _report('$name.nip44Encrypt, same peer', count, sw.elapsed);

        await signer.dispose();
      }
    });

    test('benchmark nip04 decrypt', () async {
      const count = 10;
      const message = 'Hello, NIP-04 decrypt benchmark!';
      final otherKeyPair = Bip340.generateKeyPair();

      final webSigner = WebSigner(keyPair.privateKey);
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
      _report('Bip340Signer.nip04Decrypt', count, sw.elapsed);

      // Web decrypt
      sw = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        await webSigner.decryptNip04(
          ciphertext: encrypted,
          senderPubkey: otherKeyPair.publicKey,
        );
      }
      sw.stop();
      _report('WebSigner.nip04Decrypt', count, sw.elapsed);

      await webSigner.dispose();
      await dartSigner.dispose();
    });

    test('benchmark nip44 decrypt', () async {
      const count = 10;
      const message = 'Hello, NIP-44 decrypt benchmark!';
      final ciphertextBySender = <String, String>{};
      for (var i = 0; i < count + 3; i++) {
        final sender = const Bip340SignerFactory().createWithNewKeyPair();
        ciphertextBySender[sender.publicKey] = await sender.encryptNip44(
          plaintext: message,
          recipientPubkey: keyPair.publicKey,
        );
        await sender.dispose();
      }
      final received = ciphertextBySender.entries.toList();

      for (final (name, signer) in _signers(keyPair.privateKey)) {
        Future<String> decrypt(MapEntry<String, String> message) => signer
            .decryptNip44(ciphertext: message.value, senderPubkey: message.key);

        for (final message in received.take(3)) {
          await decrypt(message);
        }

        var sw = Stopwatch()..start();
        for (final message in received.skip(3)) {
          await decrypt(message);
        }
        _report('$name.nip44Decrypt, new sender', count, sw.elapsed);

        sw = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          await decrypt(received.last);
        }
        _report('$name.nip44Decrypt, same sender', count, sw.elapsed);

        await signer.dispose();
      }
    });
  });
}
