import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip59/dostr_nip59.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

import 'mocks/memory_gift_wrap_cache.dart';

class _RejectingSigner extends Bip340Signer {
  _RejectingSigner(KeyPair key) : super(key.privateKey);

  @override
  Future<String> decryptNip44({
    required String ciphertext,
    required String senderPubkey,
  }) => throw SignerRequestRejectedException(requestId: 'decrypt');
}

void main() {
  NostrSigner? loggedSigner;
  late GiftWrap giftWrap;

  final alice = Bip340.generateKeyPair();
  final bob = Bip340.generateKeyPair();
  final carol = Bip340.generateKeyPair();

  NostrSigner signerOf(KeyPair key) => Bip340Signer(key.privateKey);

  GiftWrap giftWrapWith({GiftWrapCache? cache}) => GiftWrap(
    signer: () => loggedSigner,
    eventVerifier: Bip340EventVerifier(),
    signerFactory: const Bip340SignerFactory(),
    cache: cache,
  );

  Nip01Event rumorOf(KeyPair author, {String content = 'hello'}) =>
      Nip01Event(pubkey: author.publicKey, kind: 14, content: content);

  /// [rumor] wrapped by alice for bob, then bob logged in.
  Future<Nip01Event> wrapForBob(Nip01Event rumor) async {
    final wrap = await giftWrap.toGiftWrap(
      rumor: rumor,
      recipientPubkey: bob.publicKey,
    );
    loggedSigner = signerOf(bob);
    return wrap;
  }

  /// A wrap for bob of [payload], which no seal holds.
  Future<Nip01Event> wrapPayloadForBob(String payload) async {
    final ephemeral = const Bip340SignerFactory().createWithNewKeyPair();
    loggedSigner = signerOf(bob);
    return ephemeral.sign(
      Nip01Event(
        pubkey: ephemeral.publicKey,
        kind: GiftWrap.kGiftWrapEventKind,
        tags: [
          ['p', bob.publicKey],
        ],
        content: (await ephemeral.encryptNip44(
          plaintext: payload,
          recipientPubkey: bob.publicKey,
        )),
      ),
    );
  }

  setUp(() {
    loggedSigner = signerOf(alice);
    giftWrap = giftWrapWith();
  });

  group('GiftWrap', () {
    test('a wrap opens back to its rumor', () async {
      final rumor = giftWrap.createRumor(
        content: 'hello bob',
        kind: 14,
        tags: [
          ['p', bob.publicKey],
        ],
      );
      expect(rumor.pubkey, alice.publicKey);

      final wrap = await wrapForBob(rumor);
      expect(wrap.kind, GiftWrap.kGiftWrapEventKind);
      expect(wrap.tags, [
        ['p', bob.publicKey],
      ]);

      final received = await giftWrap.fromGiftWrap(giftWrap: wrap);
      expect(received.id, rumor.id);
      expect(received.content, rumor.content);
      expect(received.kind, rumor.kind);
      expect(received.pubkey, rumor.pubkey);
      expect(received.tags, rumor.tags);
    });

    test(
      'toGiftWrap puts additionalTags on the wrap after its p tag',
      () async {
        final wrap = await giftWrap.toGiftWrap(
          rumor: rumorOf(alice),
          recipientPubkey: bob.publicKey,
          additionalTags: [
            ['expiration', '1700000000'],
          ],
        );

        expect(wrap.tags, [
          ['p', bob.publicKey],
          ['expiration', '1700000000'],
        ]);
      },
    );

    test('wrapEvent puts additionalTags on the wrap after its p tag', () async {
      final seal = await giftWrap.sealRumor(
        rumor: rumorOf(alice),
        recipientPubkey: bob.publicKey,
      );

      final wrap = await giftWrap.wrapEvent(
        recipientPubkey: bob.publicKey,
        sealEvent: seal,
        additionalTags: [
          ['pow', '25'],
          ['client', 'test_client'],
        ],
      );

      expect(wrap.tags, [
        ['p', bob.publicKey],
        ['pow', '25'],
        ['client', 'test_client'],
      ]);
    });

    test(
      'the seal and the wrap are dated up to two days before the rumor',
      () async {
        const twoDays = 172800;
        final rumor = rumorOf(alice);

        final wrap = await wrapForBob(rumor);
        final seal = await giftWrap.unwrapEvent(wrappedEvent: wrap);

        for (final createdAt in [wrap.createdAt, seal.createdAt]) {
          expect(createdAt, greaterThanOrEqualTo(rumor.createdAt - twoDays));
          expect(createdAt, lessThan(rumor.createdAt));
        }
        expect(
          (await giftWrap.fromGiftWrap(giftWrap: wrap)).createdAt,
          rumor.createdAt,
        );
      },
    );

    test('the seal is signed by the sender', () async {
      final wrap = await wrapForBob(rumorOf(alice));

      final seal = await giftWrap.unwrapEvent(wrappedEvent: wrap);

      expect(seal.pubkey, alice.publicKey);
      expect(await Bip340EventVerifier().verify(seal), isTrue);
    });

    test('a custom signer seals and opens instead of the logged one', () async {
      final rumor = giftWrap.createRumor(
        customPubkey: carol.publicKey,
        content: 'from carol',
        kind: 14,
        tags: const [],
      );

      final wrap = await giftWrap.toGiftWrap(
        rumor: rumor,
        recipientPubkey: bob.publicKey,
        customSigner: signerOf(carol),
      );
      final received = await giftWrap.fromGiftWrap(
        giftWrap: wrap,
        customSigner: signerOf(bob),
      );

      expect(received.pubkey, carol.publicKey);
      expect(received.content, 'from carol');
    });

    test('leaves the sig of a signed rumor out of its seal', () async {
      final wrap = await wrapForBob(
        Nip01Event(
          pubkey: alice.publicKey,
          kind: 14,
          content: 'signed',
          sig: 'a' * 128,
        ),
      );

      final rumor = await giftWrap.fromGiftWrap(giftWrap: wrap);

      expect(rumor.content, 'signed');
      expect(rumor.sig, isNull);
    });
  });

  group('refuses', () {
    test('an event that is not a gift wrap', () async {
      final note = Nip01Event(pubkey: alice.publicKey, kind: 1, content: '');

      await expectLater(
        giftWrap.fromGiftWrap(giftWrap: note),
        throwsArgumentError,
      );
      await expectLater(
        giftWrap.fromGiftWrapWithInfo(giftWrap: note),
        throwsArgumentError,
      );
      await expectLater(
        giftWrap.tryFromGiftWrapFromCache(giftWrap: note),
        throwsArgumentError,
      );
    });

    test('a wrap for someone else', () async {
      final wrap = await wrapForBob(rumorOf(alice));
      loggedSigner = signerOf(carol);

      await expectLater(
        giftWrap.fromGiftWrap(giftWrap: wrap),
        throwsA(
          isA<GiftWrapDecryptionException>()
              .having((e) => e.eventId, 'eventId', wrap.id)
              .having((e) => e.cause, 'cause', isNotNull),
        ),
      );
    });

    test(
      'a seal whose signature is wrong, unless told not to verify',
      () async {
        final seal = await giftWrap.sealRumor(
          rumor: rumorOf(alice, content: 'forged seal'),
          recipientPubkey: bob.publicKey,
        );
        final wrap = await giftWrap.wrapEvent(
          recipientPubkey: bob.publicKey,
          sealEvent: seal.copyWith(sig: '0' * 128),
        );
        loggedSigner = signerOf(bob);

        await expectLater(
          giftWrap.fromGiftWrap(giftWrap: wrap),
          throwsA(isA<InvalidGiftWrapException>()),
        );
        final result = await giftWrap.fromGiftWrapWithInfo(giftWrap: wrap);
        expect(result.isGiftWrapSignatureValid, isTrue);
        expect(result.isSealSignatureValid, isFalse);
        expect(result.isCryptographicallyValid, isFalse);
        expect(
          (await giftWrap.fromGiftWrap(
            giftWrap: wrap,
            verifySignature: false,
          )).content,
          'forged seal',
        );
      },
    );

    test('a wrap whose signature is wrong, in fromGiftWrapWithInfo', () async {
      final wrap = await wrapForBob(rumorOf(alice));

      final result = await giftWrap.fromGiftWrapWithInfo(
        giftWrap: wrap.copyWith(sig: '0' * 128),
      );

      expect(result.isGiftWrapSignatureValid, isFalse);
      expect(result.isSealSignatureValid, isTrue);
      expect(result.isCryptographicallyValid, isFalse);
    });

    test('a rumor of another pubkey than the seal', () async {
      final wrap = await wrapForBob(rumorOf(carol, content: 'not from carol'));

      await expectLater(
        giftWrap.fromGiftWrap(giftWrap: wrap),
        throwsA(isA<InvalidGiftWrapException>()),
      );
      final result = await giftWrap.fromGiftWrapWithInfo(giftWrap: wrap);
      expect(result.isPubkeyMatch, isFalse);
      expect(result.isCryptographicallyValid, isFalse);
    });

    test('a rumor whose id does not match its content', () async {
      final wrap = await wrapForBob(
        Nip01Event(
          id: 'f' * 64,
          pubkey: alice.publicKey,
          kind: 14,
          content: 'forged id',
        ),
      );

      await expectLater(
        giftWrap.fromGiftWrap(giftWrap: wrap),
        throwsA(isA<InvalidGiftWrapException>()),
      );
      final result = await giftWrap.fromGiftWrapWithInfo(giftWrap: wrap);
      expect(result.isRumorIdValid, isFalse);
      expect(result.isCryptographicallyValid, isFalse);
    });

    test('a payload that is not an event', () async {
      for (final payload in ['not json', '{"kind": 13}']) {
        final wrap = await wrapPayloadForBob(payload);

        await expectLater(
          giftWrap.fromGiftWrap(giftWrap: wrap),
          throwsA(isA<InvalidGiftWrapException>()),
          reason: payload,
        );
      }
    });
  });

  group('signer', () {
    test('without one, throws GiftWrapNoSignerException', () async {
      final wrap = await wrapForBob(rumorOf(alice));
      loggedSigner = null;

      expect(
        () => giftWrap.createRumor(content: '', kind: 14, tags: const []),
        throwsA(isA<GiftWrapNoSignerException>()),
      );
      await expectLater(
        giftWrap.toGiftWrap(
          rumor: rumorOf(alice),
          recipientPubkey: bob.publicKey,
        ),
        throwsA(isA<GiftWrapNoSignerException>()),
      );
      await expectLater(
        giftWrap.fromGiftWrap(giftWrap: wrap),
        throwsA(isA<GiftWrapNoSignerException>()),
      );
    });

    test('a recipient it cannot encrypt for', () async {
      await expectLater(
        giftWrap.toGiftWrap(rumor: rumorOf(alice), recipientPubkey: 'f' * 64),
        throwsA(
          isA<GiftWrapEncryptionException>()
              .having((e) => e.recipientPubkey, 'recipientPubkey', 'f' * 64)
              .having((e) => e.cause, 'cause', isNotNull),
        ),
      );
    });

    test('a request the user rejects passes through', () async {
      final wrap = await wrapForBob(rumorOf(alice));

      await expectLater(
        giftWrap.fromGiftWrap(
          giftWrap: wrap,
          customSigner: _RejectingSigner(bob),
        ),
        throwsA(isA<SignerRequestRejectedException>()),
      );
    });
  });

  group('cache', () {
    test('the cache-only unwrap returns null without a cache', () async {
      final wrap = await wrapForBob(rumorOf(alice));
      loggedSigner = null;

      expect(await giftWrap.tryFromGiftWrapFromCache(giftWrap: wrap), isNull);
    });

    test('an unwrap fills the cache, later unwraps reuse it', () async {
      final cache = MemoryGiftWrapCache();
      final cached = giftWrapWith(cache: cache);
      final wrap = await wrapForBob(rumorOf(alice));

      expect(await cached.tryFromGiftWrapFromCache(giftWrap: wrap), isNull);

      final rumor = await cached.fromGiftWrap(giftWrap: wrap);
      expect(cache.decryptions, 2);
      expect(
        (await cached.tryFromGiftWrapFromCache(giftWrap: wrap))?.id,
        rumor.id,
      );

      await cached.fromGiftWrap(giftWrap: wrap);
      expect(cache.decryptions, 2);
    });

    test('a failed decryption is not cached', () async {
      final cache = MemoryGiftWrapCache();
      final cached = giftWrapWith(cache: cache);
      final wrap = await wrapForBob(rumorOf(alice));
      loggedSigner = signerOf(carol);

      await expectLater(
        cached.fromGiftWrap(giftWrap: wrap),
        throwsA(isA<GiftWrapDecryptionException>()),
      );
      expect(cache.plaintexts, isEmpty);
    });
  });
}
