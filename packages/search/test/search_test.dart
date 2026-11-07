import 'dart:convert';

import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_metadatas/ndk_metadatas.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_search/ndk_search.dart';
import 'package:test/test.dart';

import 'mocks/fake_network.dart';

void main() {
  final key0 = Bip340.generatePrivateKey();
  final key1 = Bip340.generatePrivateKey();

  late FakeRelays relays;
  late MemorySearchCache cache;
  late Search search;

  setUp(() {
    relays = FakeRelays();
    cache = MemorySearchCache();
    search = Search(query: relays.query, cache: cache);
  });

  Nip01Event note(String pubKey, String content, {int createdAt = 100}) =>
      Nip01Event(
        pubKey: pubKey,
        kind: 1,
        tags: const [],
        content: content,
        createdAt: createdAt,
      );

  group('metadataSearch', () {
    test('answers from the cache with the given limit', () async {
      cache.events.addAll([
        Nip01Event(
          pubKey: key0.publicKey,
          kind: Metadata.kKind,
          tags: const [],
          content: jsonEncode({'name': 'alice'}),
          createdAt: 100,
        ),
        Nip01Event(
          pubKey: key1.publicKey,
          kind: Metadata.kKind,
          tags: const [],
          content: jsonEncode({'name': 'bob'}),
          createdAt: 100,
        ),
      ]);

      final found = await search.metadataSearch('ali', limit: 3);

      expect(found.map((m) => m.pubKey), [key0.publicKey]);
      expect(cache.metadataSearches.single, (search: 'ali', limit: 3));
      expect(relays.queries, isEmpty);
    });

    test('defaults to 10 results', () async {
      await search.metadataSearch('alice');

      expect(cache.metadataSearches.single.limit, 10);
    });
  });

  group('searchEvents', () {
    test('with cacheOnly, answers from the cache alone', () async {
      final cached = note(key0.publicKey, 'cached lightning');
      cache.events.add(cached);
      relays.events.add(note(key1.publicKey, 'relay lightning'));

      final found = await search.searchEvents(
        search: 'lightning',
        cacheOnly: true,
      );

      expect(found, [cached]);
      expect(relays.queries, isEmpty);
    });

    test('merges cached and relay events without duplicates', () async {
      final shared = note(key0.publicKey, 'both');
      final cachedOnly = note(key0.publicKey, 'cache', createdAt: 101);
      final relayOnly = note(key1.publicKey, 'relay', createdAt: 102);
      cache.events.addAll([shared, cachedOnly]);
      relays.events.addAll([shared, relayOnly]);

      final found = await search.searchEvents(kinds: [1]);

      expect(found, unorderedEquals([shared, cachedOnly, relayOnly]));
    });

    test('passes the criteria to the cache and to relays', () async {
      await search.searchEvents(
        ids: ['id0'],
        authors: [key0.publicKey],
        kinds: [1],
        tags: {
          't': ['nostr'],
        },
        since: 10,
        until: 20,
        search: 'lightning',
        limit: 5,
      );

      final load = cache.loads.single;
      expect(load.ids, ['id0']);
      expect(load.pubKeys, [key0.publicKey]);
      expect(load.kinds, [1]);
      expect(load.tags, {
        't': ['nostr'],
      });
      expect(load.since, 10);
      expect(load.until, 20);
      expect(load.search, 'lightning');
      expect(load.limit, 5);
      final filter = relays.queries.single;
      expect(filter.authors, [key0.publicKey]);
      expect(filter.kinds, [1]);
      expect(filter.tags, {
        't': ['nostr'],
      });
      expect(filter.since, 10);
      expect(filter.until, 20);
      expect(filter.search, 'lightning');
      expect(filter.limit, 5);
    });

    test('defaults to 100 results', () async {
      await search.searchEvents(search: 'lightning');

      expect(cache.loads.single.limit, 100);
      expect(relays.queries.single.limit, 100);
    });
  });
}
