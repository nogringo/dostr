import 'dart:async';

import 'package:test/test.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_requests/ndk_requests.dart';

/// The events [cacheRead] found for [request], and the filters it left.
Future<(List<Nip01Event>, List<Filter>)> resolve(
  CacheRead cacheRead,
  NdkRequest request,
) async {
  final found = StreamController<Nip01Event>();
  final events = found.stream.toList();
  final remaining = await cacheRead.resolveUnresolvedFilters(
    filters: request.filters,
    outController: found,
  );
  return (await events, remaining);
}

void main() async {
  group('CacheRead', () {
    final CacheManager myCacheManager = MemCacheManager();

    final List<Nip01Event> myEvens = [
      Nip01Event(pubKey: "pubKey1", kind: 1, tags: [], content: "content1_a"),
      Nip01Event(pubKey: "pubKey1", kind: 1, tags: [], content: "content1_b"),
      Nip01Event(pubKey: "pubKey1", kind: 1, tags: [], content: "content1_c"),
      Nip01Event(pubKey: "pubKey2", kind: 1, tags: [], content: "content2_a"),
      Nip01Event(pubKey: "pubKey2", kind: 1, tags: [], content: "content2_b"),
      Nip01Event(pubKey: "pubKey2", kind: 1, tags: [], content: "content2_c"),
    ];

    setUp(() async {
      await myCacheManager.saveEvents(myEvens);
    });

    test('cache read - all - BAD TEST', skip: true, () async {
      final NdkRequest myNdkRequest = NdkRequest.query(
        "id",
        filters: [
          Filter(authors: ['pubKey1', 'pubKey2'], kinds: [1]),
        ],
        timeoutDuration: Duration(seconds: 5),
      );
      final CacheRead myUsecase = CacheRead(myCacheManager);

      final (data, unresolvedFilters) = await resolve(myUsecase, myNdkRequest);

      expect(data, unorderedEquals(myEvens));

      for (final filter in unresolvedFilters) {
        expect(filter.authors, equals([]));
      }
    });

    test('cache read - some missing - BAD TEST', skip: true, () async {
      final NdkRequest myNdkRequest = NdkRequest.query(
        "id",
        filters: [
          Filter(
            authors: ['pubKey1', 'pubKey2', 'notInCachePubKey'],
            kinds: [1],
          ),
        ],
        timeoutDuration: Duration(seconds: 5),
      );
      final CacheRead myUsecase = CacheRead(myCacheManager);

      final (data, unresolvedFilters) = await resolve(myUsecase, myNdkRequest);

      expect(data, unorderedEquals(myEvens));

      for (final filter in unresolvedFilters) {
        expect(filter.authors, equals(['notInCachePubKey']));
      }
    });

    test(
      'cache read - author removal based on limit - remove - BAD TEST',
      skip: true,
      () async {
        final CacheRead myUsecase = CacheRead(myCacheManager);

        // Test with limit
        final NdkRequest myNdkRequestWithLimit = NdkRequest.query(
          "author-remove",
          filters: [
            Filter(authors: ['pubKey1', 'pubKey2'], kinds: [1], limit: 2),
          ],
          timeoutDuration: Duration(seconds: 5),
        );
        final (_, unresolvedFilters) = await resolve(
          myUsecase,
          myNdkRequestWithLimit,
        );

        expect(unresolvedFilters[0].authors, equals([]));
      },
    );

    test('cache read - not all in cache - BAD TEST', skip: true, () async {
      final CacheRead myUsecase = CacheRead(myCacheManager);

      // Test with limit
      final NdkRequest myNdkRequestWithLimit = NdkRequest.query(
        "author-not-covered",
        filters: [
          Filter(
            authors: [
              'pubKey1',
              'pubKey2',
              'notInCachePubKey1',
              'notInCachePubKey2',
            ],
            kinds: [1],
            limit: 200, // some high limit
          ),
        ],
        timeoutDuration: Duration(seconds: 5),
      );
      final (_, unresolvedFilters) = await resolve(
        myUsecase,
        myNdkRequestWithLimit,
      );

      expect(
        unresolvedFilters[0].authors,
        equals([
          'pubKey1',
          'pubKey2',
          'notInCachePubKey1',
          'notInCachePubKey2',
        ]),
      );
    });

    test('cache read - id filter with one missing', () async {
      final CacheManager myCacheManager = MemCacheManager();
      final CacheRead myUsecase = CacheRead(myCacheManager);

      final eventId0 = Nip01Event(
        pubKey: "pubKey0",
        kind: 1,
        tags: [],
        content: "content0",
        id: "id0",
        sig: null,
      );

      final eventId1 = Nip01Event(
        pubKey: "pubKey1",
        kind: 1,
        tags: [],
        content: "content1",
        id: "id1",
        sig: null,
      );

      final eventId2 = Nip01Event(
        pubKey: "pubKey2",
        kind: 1,
        tags: [],
        content: "content2",
        id: "id2",
        sig: null,
      );

      final List<Nip01Event> idEvents = [eventId0, eventId1, eventId2];

      await myCacheManager.saveEvents(idEvents);

      final NdkRequest myNdkRequest = NdkRequest.query(
        "id-filter",
        filters: [
          Filter(ids: ['id0', 'id1', 'id2', 'id3'], kinds: [1]),
        ],
        timeoutDuration: Duration(seconds: 5),
      );
      final (foundEvents, unresolvedFilters) = await resolve(
        myUsecase,
        myNdkRequest,
      );
      expect(foundEvents.length, equals(3));
      expect(
        foundEvents.map((e) => e.id).toSet(),
        equals({'id0', 'id1', 'id2'}),
      );

      expect(unresolvedFilters[0].ids, equals(['id3']));
    });

    test('cache read - id filter all in cache', () async {
      final CacheManager myCacheManager = MemCacheManager();
      final CacheRead myUsecase = CacheRead(myCacheManager);

      final eventId0 = Nip01Event(
        pubKey: "pubKey0",
        kind: 1,
        tags: [],
        content: "content0",
        id: "id0",
        sig: null,
      );

      final eventId1 = Nip01Event(
        pubKey: "pubKey1",
        kind: 1,
        tags: [],
        content: "content1",
        id: "id1",
        sig: null,
      );

      final eventId2 = Nip01Event(
        pubKey: "pubKey2",
        kind: 1,
        tags: [],
        content: "content2",
        id: "id2",
        sig: null,
      );

      final List<Nip01Event> idEvents = [eventId0, eventId1, eventId2];

      await myCacheManager.saveEvents(idEvents);

      final NdkRequest myNdkRequest = NdkRequest.query(
        "id-filter",
        filters: [
          Filter(ids: ['id0', 'id1', 'id2'], kinds: [1]),
        ],
        timeoutDuration: Duration(seconds: 5),
      );
      final (foundEvents, unresolvedFilters) = await resolve(
        myUsecase,
        myNdkRequest,
      );
      expect(foundEvents.length, equals(3));
      expect(
        foundEvents.map((e) => e.id).toSet(),
        equals({'id0', 'id1', 'id2'}),
      );

      expect(unresolvedFilters, equals([]));
    });

    test('cache read - has events for all authors', () async {
      // ...but we cannot remove them from the filter because only replaceable events have 1 event per pubKey+kind, normal events can have many per pubKey+kind
      final filter = Filter(authors: ['pubKey1', 'pubKey2'], kinds: [1]);
      final NdkRequest myNdkRequest = NdkRequest.query(
        "id",
        filters: [filter],
        timeoutDuration: Duration(seconds: 5),
      );
      final CacheRead myUsecase = CacheRead(myCacheManager);

      final (data, unresolvedFilters) = await resolve(myUsecase, myNdkRequest);

      expect(data, unorderedEquals(myEvens));

      /// expect in any order

      expect(unresolvedFilters, unorderedEquals([filter]));
    });

    group('applies every field of the filter', () {
      late CacheManager cache;
      late CacheRead cacheRead;

      Future<(List<Nip01Event>, List<Filter>)> read(Filter filter) => resolve(
        cacheRead,
        NdkRequest.query(
          "every-field",
          filters: [filter],
          timeoutDuration: Duration(seconds: 5),
        ),
      );

      final tagged = Nip01Event(
        pubKey: "author",
        kind: 1,
        tags: [
          ["t", "nostr"],
        ],
        content: "a tagged note",
      );
      final untagged = Nip01Event(
        pubKey: "author",
        kind: 1,
        tags: [],
        content: "another note",
      );
      final reaction = Nip01Event(
        pubKey: "author",
        kind: 7,
        tags: [],
        content: "+",
      );

      setUp(() async {
        cache = MemCacheManager();
        cacheRead = CacheRead(cache);
        await cache.saveEvents([tagged, untagged, reaction]);
      });

      test('tags, next to authors', () async {
        final (found, _) = await read(
          Filter(authors: ["author"], kinds: [1], tTags: ["nostr"]),
        );
        expect(found.map((e) => e.id), [tagged.id]);
      });

      test('search, next to authors', () async {
        final (found, _) = await read(
          Filter(authors: ["author"], search: "another"),
        );
        expect(found.map((e) => e.id), [untagged.id]);
      });

      test('ids, next to authors', () async {
        final (found, _) = await read(
          Filter(ids: [tagged.id], authors: ["author"]),
        );
        expect(found.map((e) => e.id), [tagged.id]);
      });

      test('kinds, next to ids, which keeps the id that missed', () async {
        final (found, remaining) = await read(
          Filter(ids: [tagged.id, reaction.id], kinds: [1]),
        );
        expect(found.map((e) => e.id), [tagged.id]);
        expect(remaining.single.ids, [reaction.id]);
      });
    });
  });
}
