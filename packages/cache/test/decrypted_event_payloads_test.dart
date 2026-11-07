import 'dart:async';

import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_nip59/ndk_nip59.dart';
import 'package:test/test.dart';

void main() {
  group('DecryptedEventPayloads', () {
    late CacheManager cacheManager;
    late DecryptedEventPayloads usecase;
    late Nip01Event event;

    setUp(() {
      cacheManager = MemCacheManager();
      usecase = DecryptedEventPayloads(cacheManager: cacheManager);
      event = Nip01Event(
        pubKey: 'author-pubkey',
        kind: 4,
        tags: const [],
        content: 'ciphertext',
      );
    });

    test('decrypts on miss and persists plaintext sidecar', () async {
      final plaintext = await usecase.loadOrDecrypt(
        event: event,
        viewerPubKey: 'viewer-pubkey',
        scheme: DecryptedPayloadScheme.nip44,
        decrypt: () async => 'hello plaintext',
      );

      expect(plaintext, 'hello plaintext');

      final stored = await cacheManager.loadDecryptedEventPayloadRecord(
        eventId: event.id,
        viewerPubKey: 'viewer-pubkey',
      );

      expect(stored, isNotNull);
      expect(stored!.status, DecryptedPayloadStatus.ready);
      expect(stored.plaintextContent, 'hello plaintext');
      expect(stored.scheme, DecryptedPayloadScheme.nip44);
      expect(stored.sourceEventPubKey, event.pubKey);
      expect(stored.sourceEventKind, event.kind);
    });

    test('returns cached plaintext without calling decrypt again', () async {
      await cacheManager.saveDecryptedEventPayloadRecord(
        DecryptedEventPayloadRecord(
          eventId: event.id,
          viewerPubKey: 'viewer-pubkey',
          scheme: DecryptedPayloadScheme.nip44,
          status: DecryptedPayloadStatus.ready,
          plaintextContent: 'cached plaintext',
          createdAt: 1,
          updatedAt: 1,
          decryptedAt: 1,
          sourceEventPubKey: event.pubKey,
          sourceEventKind: event.kind,
        ),
      );

      var decryptCalls = 0;
      final plaintext = await usecase.loadOrDecrypt(
        event: event,
        viewerPubKey: 'viewer-pubkey',
        scheme: DecryptedPayloadScheme.nip44,
        decrypt: () async {
          decryptCalls += 1;
          return 'should not happen';
        },
      );

      expect(plaintext, 'cached plaintext');
      expect(decryptCalls, 0);
    });

    test('persists classified decrypt failures and rethrows', () async {
      await expectLater(
        () => usecase.loadOrDecrypt(
          event: event,
          viewerPubKey: 'viewer-pubkey',
          scheme: DecryptedPayloadScheme.nip44,
          decrypt: () async => throw StateError('boom'),
          classifyFailure: (_, _) => DecryptedPayloadStatus.permanentFailure,
        ),
        throwsA(isA<StateError>()),
      );

      final stored = await cacheManager.loadDecryptedEventPayloadRecord(
        eventId: event.id,
        viewerPubKey: 'viewer-pubkey',
      );
      expect(stored, isNotNull);
      expect(stored!.status, DecryptedPayloadStatus.permanentFailure);
      expect(stored.failureReason, contains('boom'));
      expect(stored.plaintextContent, isNull);
    });

    test(
      'coalesces concurrent decrypts for the same event and viewer',
      () async {
        var decryptCalls = 0;

        final futures = List.generate(
          2,
          (_) => usecase.loadOrDecrypt(
            event: event,
            viewerPubKey: 'viewer-pubkey',
            scheme: DecryptedPayloadScheme.nip44,
            decrypt: () async {
              decryptCalls += 1;
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return 'shared plaintext';
            },
          ),
        );

        final results = await Future.wait(futures);

        expect(results, ['shared plaintext', 'shared plaintext']);
        expect(decryptCalls, 1);
      },
    );
  });

  group('decrypted payload caches', () {
    late CacheManager cacheManager;
    late DecryptedEventPayloads payloads;

    setUp(() {
      cacheManager = MemCacheManager();
      payloads = DecryptedEventPayloads(cacheManager: cacheManager);
    });

    Future<DecryptedPayloadScheme?> schemeOf(Nip01Event event) async =>
        (await cacheManager.loadDecryptedEventPayloadRecord(
          eventId: event.id,
          viewerPubKey: 'viewer',
        ))?.scheme;

    Nip01Event eventOf(int kind, String content) => Nip01Event(
      pubKey: 'author',
      kind: kind,
      tags: const [],
      content: content,
    );

    test('stores a gift wrap as giftWrap and its seal as nip44', () async {
      final cache = DecryptedPayloadsGiftWrapCache(payloads);
      final wrap = eventOf(GiftWrap.kGiftWrapEventkind, 'wrap');
      final seal = eventOf(13, 'seal');
      for (final event in [wrap, seal]) {
        await cache.loadOrDecrypt(
          event: event,
          viewerPubKey: 'viewer',
          decrypt: () async => 'plaintext',
        );
      }

      expect(await schemeOf(wrap), DecryptedPayloadScheme.giftWrap);
      expect(await schemeOf(seal), DecryptedPayloadScheme.nip44);
      expect(
        await cache.loadCachedPlaintext(
          eventId: wrap.id,
          viewerPubKey: 'viewer',
        ),
        'plaintext',
      );
    });

    test('stores a NIP-04 list as nip04 and others as nip44', () async {
      final cache = DecryptedPayloadsNip51ListCache(payloads);
      final nip04 = eventOf(10000, 'cipher?iv=abc');
      final nip44 = eventOf(10000, 'cipher');
      for (final event in [nip04, nip44]) {
        await cache.loadOrDecrypt(
          event: event,
          viewerPubKey: 'viewer',
          decrypt: () async => '[]',
        );
      }

      expect(await schemeOf(nip04), DecryptedPayloadScheme.nip04);
      expect(await schemeOf(nip44), DecryptedPayloadScheme.nip44);
    });
  });
}
