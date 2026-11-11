import 'dart:convert';

import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_metadata/ndk_metadata.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:test/test.dart';

import 'mocks/fake_network.dart';

void main() {
  final key0 = Bip340.generatePrivateKey();
  final key1 = Bip340.generatePrivateKey();

  late FakeRelays relays;
  late MemoryMetadataCache cache;
  late Accounts accounts;
  late Metadatas metadatas;

  setUp(() {
    relays = FakeRelays();
    cache = MemoryMetadataCache();
    accounts = Accounts(const Bip340EventSignerFactory());
    metadatas = Metadatas(
      query: relays.query,
      publish: relays.publish,
      cache: cache,
      accounts: accounts,
    );
  });

  tearDown(() => accounts.dispose());

  void login() => accounts.loginPrivateKey(
    pubkey: key0.publicKey,
    privkey: key0.privateKey!,
  );

  Nip01Event metadataEvent(
    String pubKey,
    Map<String, dynamic> content, {
    required int createdAt,
    List<List<String>> tags = const [],
  }) => Nip01Event(
    pubKey: pubKey,
    kind: Metadata.kKind,
    tags: tags,
    content: jsonEncode(content),
    createdAt: createdAt,
  );

  group('loadMetadata', () {
    test('answers from the cache without asking relays', () async {
      await cache.saveEvent(
        metadataEvent(key0.publicKey, {'name': 'cached'}, createdAt: 100),
      );
      relays.metadatas[key0.publicKey] = metadataEvent(key0.publicKey, {
        'name': 'network',
      }, createdAt: 200);

      final metadata = await metadatas.loadMetadata(key0.publicKey);

      expect(metadata!.name, 'cached');
      expect(relays.queries, isEmpty);
    });

    test('asks relays when nothing is cached and caches the answer', () async {
      relays.metadatas[key0.publicKey] = metadataEvent(key0.publicKey, {
        'name': 'network',
      }, createdAt: 200);

      final metadata = await metadatas.loadMetadata(
        key0.publicKey,
        idleTimeout: const Duration(seconds: 2),
      );

      expect(metadata!.name, 'network');
      expect(metadata.refreshedTimestamp, isNotNull);
      expect(relays.queries.single.cacheRead, isTrue);
      expect(relays.queries.single.timeout, const Duration(seconds: 2));
      expect(relays.queries.single.filter.authors, [key0.publicKey]);
      expect((await cache.loadMetadata(key0.publicKey))!.name, 'network');
    });

    test('forceRefresh skips cached events and takes the relays one', () async {
      await cache.saveEvent(
        metadataEvent(key0.publicKey, {'name': 'cached'}, createdAt: 300),
      );
      relays.metadatas[key0.publicKey] = metadataEvent(key0.publicKey, {
        'name': 'network',
      }, createdAt: 200);

      final metadata = await metadatas.loadMetadata(
        key0.publicKey,
        forceRefresh: true,
      );

      expect(metadata!.name, 'network');
      expect(relays.queries.single.cacheRead, isFalse);
    });

    test('answers null when relays fail and nothing is cached', () async {
      relays.queryError = StateError('timeout');

      expect(await metadatas.loadMetadata(key0.publicKey), isNull);
    });
  });

  group('loadMetadatas', () {
    test('asks relays only for the missing pubkeys', () async {
      await cache.saveEvent(
        metadataEvent(key0.publicKey, {'name': 'cached'}, createdAt: 100),
      );
      relays.metadatas[key1.publicKey] = metadataEvent(key1.publicKey, {
        'name': 'network',
      }, createdAt: 100);
      final loaded = <Metadata>[];

      final result = await metadatas.loadMetadatas(
        [key0.publicKey, key1.publicKey],
        ['wss://relay.example.com'],
        onLoad: loaded.add,
      );

      expect(result.map((m) => m.name), unorderedEquals(['cached', 'network']));
      expect(loaded.single.pubKey, key1.publicKey);
      expect(relays.queries.single.filter.authors, [key1.publicKey]);
      expect(relays.queries.single.relays, ['wss://relay.example.com']);
      expect(await cache.loadMetadata(key1.publicKey), isNotNull);
    });

    test('does not ask relays when everything is cached', () async {
      await cache.saveEvent(
        metadataEvent(key0.publicKey, {'name': 'cached'}, createdAt: 100),
      );

      final result = await metadatas.loadMetadatas([key0.publicKey], null);

      expect(result.single.name, 'cached');
      expect(relays.queries, isEmpty);
    });
  });

  group('broadcastMetadata', () {
    test('needs a logged account', () async {
      expect(
        () => metadatas.broadcastMetadata(Metadata(name: 'alice')),
        throwsA('Not logged in'),
      );
      expect(relays.published, isEmpty);
    });

    test(
      'merges over the latest published content and keeps its tags',
      () async {
        login();
        relays.metadatas[key0.publicKey] = metadataEvent(
          key0.publicKey,
          {'name': 'old', 'website': 'https://example.com'},
          createdAt: 100,
          tags: [
            ['i', 'github:alice', 'proof'],
          ],
        );

        final broadcasted = await metadatas.broadcastMetadata(
          Metadata(name: 'alice'),
          specificRelays: ['wss://relay.example.com'],
        );

        final published = relays.published.single;
        expect(published.relays, ['wss://relay.example.com']);
        expect(published.event.pubKey, key0.publicKey);
        expect(jsonDecode(published.event.content), {
          'name': 'alice',
          'website': 'https://example.com',
        });
        expect(published.event.tags, [
          ['i', 'github:alice', 'proof'],
        ]);
        expect(broadcasted.name, 'alice');
        expect(broadcasted.website, 'https://example.com');
        expect(cache.events.single.id, published.event.id);
      },
    );

    test('uses the given tags when nothing was published yet', () async {
      login();

      await metadatas.broadcastMetadata(
        Metadata(
          name: 'alice',
          tags: [
            ['i', 'github:alice', 'proof'],
          ],
        ),
      );

      expect(relays.published.single.event.tags, [
        ['i', 'github:alice', 'proof'],
      ]);
      expect(relays.published.single.relays, isNull);
    });
  });
}
