import 'dart:async';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';
import 'package:test/test.dart';

class _CountingSigner extends Bip340Signer {
  int decryptions = 0;

  _CountingSigner(KeyPair key) : super(key.privateKey);

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) {
    decryptions++;
    return super.decryptNip44(
      ciphertext: ciphertext,
      senderPubkey: senderPubkey,
    );
  }
}

class _GatedSigner extends Bip340Signer {
  final Future<void> gate;

  _GatedSigner(KeyPair key, this.gate) : super(key.privateKey);

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) async {
    await gate;
    return super.decryptNip44(
      ciphertext: ciphertext,
      senderPubkey: senderPubkey,
    );
  }
}

class _RecordingCache extends MemoryDecryptionCache {
  final List<(String, String)> saves = [];

  @override
  Future<void> save({
    required String accountPubkey,
    required String key,
    required String plaintext,
  }) {
    saves.add((accountPubkey, key));
    return super.save(
      accountPubkey: accountPubkey,
      key: key,
      plaintext: plaintext,
    );
  }
}

void main() {
  const factory = Bip340SignerFactory();

  runSignerTestSuite(
    name: 'CachedNostrSigner',
    createSigner: () => CachedNostrSigner(
      factory.createWithNewKeyPair(),
      cache: MemoryDecryptionCache(),
    ),
    createPeer: factory.createWithNewKeyPair,
    createReadOnlySigner: () => CachedNostrSigner(
      factory.readOnly(factory.generateKeyPair().publicKey),
      cache: MemoryDecryptionCache(),
    ),
    verifier: Bip340EventVerifier(),
  );

  group('CachedNostrSigner', () {
    late _CountingSigner inner;
    late MemoryDecryptionCache cache;
    late CachedNostrSigner signer;
    late NostrSigner peer;
    late String ciphertext;

    setUp(() async {
      inner = _CountingSigner(factory.generateKeyPair());
      cache = MemoryDecryptionCache();
      signer = CachedNostrSigner(inner, cache: cache);
      peer = factory.createWithNewKeyPair();
      ciphertext = await peer.encryptNip44(
        plaintext: 'hello',
        recipientPubkey: signer.publicKey,
      );
    });

    Future<String> decrypt({String? senderPubkey}) => signer.decryptNip44(
      ciphertext: ciphertext,
      senderPubkey: senderPubkey ?? peer.publicKey,
    );

    test('asks its signer once per ciphertext', () async {
      expect(await Future.wait([decrypt(), decrypt()]), ['hello', 'hello']);
      expect(await decrypt(), 'hello');

      expect(inner.decryptions, 1);
    });

    test('reads its cache alone without asking the signer', () async {
      Future<String?> fromCache() => signer.decryptNip44FromCache(
        ciphertext: ciphertext,
        senderPubkey: peer.publicKey,
      );

      expect(await fromCache(), isNull);
      await decrypt();

      expect(await fromCache(), 'hello');
      expect(inner.decryptions, 1);
    });

    test('stores a plaintext under an opaque key, with its account', () async {
      final recording = _RecordingCache();
      final cached = CachedNostrSigner(inner, cache: recording);

      await cached.decryptNip44(
        ciphertext: ciphertext,
        senderPubkey: peer.publicKey,
      );

      final (account, key) = recording.saves.single;
      expect(account, cached.publicKey);
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('keys a plaintext by its account and its sender', () async {
      await decrypt();
      final other = CachedNostrSigner(
        factory.createWithNewKeyPair(),
        cache: cache,
      );

      await expectLater(
        decrypt(senderPubkey: other.publicKey),
        throwsA(isA<SignerRequestFailedException>()),
      );
      expect(
        await other.decryptNip44FromCache(
          ciphertext: ciphertext,
          senderPubkey: peer.publicKey,
        ),
        isNull,
      );
    });

    test('clears the plaintexts of its own pubkey alone', () async {
      final other = CachedNostrSigner(
        factory.createWithNewKeyPair(),
        cache: cache,
      );
      final otherCiphertext = await peer.encryptNip44(
        plaintext: 'hi',
        recipientPubkey: other.publicKey,
      );
      await decrypt();
      await other.decryptNip44(
        ciphertext: otherCiphertext,
        senderPubkey: peer.publicKey,
      );

      await signer.clearCache();

      expect(
        await signer.decryptNip44FromCache(
          ciphertext: ciphertext,
          senderPubkey: peer.publicKey,
        ),
        isNull,
      );
      expect(
        await other.decryptNip44FromCache(
          ciphertext: otherCiphertext,
          senderPubkey: peer.publicKey,
        ),
        'hi',
      );
    });

    test('does not store a decryption that ends after a clear', () async {
      final gate = Completer<void>();
      final gated = CachedNostrSigner(
        _GatedSigner(factory.generateKeyPair(), gate.future),
        cache: cache,
      );
      final lateCiphertext = await peer.encryptNip44(
        plaintext: 'late',
        recipientPubkey: gated.publicKey,
      );

      final decryption = gated.decryptNip44(
        ciphertext: lateCiphertext,
        senderPubkey: peer.publicKey,
      );
      await gated.clearCache();
      gate.complete();

      expect(await decryption, 'late');
      expect(
        await gated.decryptNip44FromCache(
          ciphertext: lateCiphertext,
          senderPubkey: peer.publicKey,
        ),
        isNull,
      );
    });

    test('does not keep a failed decryption', () async {
      final stranger = factory.createWithNewKeyPair();

      for (var i = 0; i < 2; i++) {
        await expectLater(
          decrypt(senderPubkey: stranger.publicKey),
          throwsA(isA<SignerRequestFailedException>()),
        );
      }

      expect(inner.decryptions, 2);
    });
  });
}
