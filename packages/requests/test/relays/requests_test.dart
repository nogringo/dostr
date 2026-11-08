import '../mocks/requests_client.dart';
import 'dart:async';

import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';
import 'package:ndk_requests/ndk_requests.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';

import '../mocks/mock_event_verifier.dart';

void main() async {
  KeyPair key1 = Bip340.generatePrivateKey();
  KeyPair key2 = Bip340.generatePrivateKey();
  KeyPair key3 = Bip340.generatePrivateKey();
  KeyPair key4 = Bip340.generatePrivateKey();

  Map<KeyPair, String> keyNames = {
    key1: "key1",
    key2: "key2",
    key3: "key3",
    key4: "key4",
  };

  Nip01Event textNote(KeyPair key2) {
    return Nip01Event(
      kind: Nip01Event.kTextNoteKind,
      pubKey: key2.publicKey,
      content: "some note from key ${keyNames[key2]}",
      tags: [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<KeyPair, Nip01Event> textNotes = {
    key1: textNote(key1),
    key2: textNote(key2),
  };

  Future<void> waitForEventCount(
    List<Nip01Event> events,
    int expectedCount, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (events.length < expectedCount) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Timed out waiting for $expectedCount events, received ${events.length}',
        );
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  group('Requests', () {
    test('Request text note with single filter parameter', () async {
      MockRelay relay1 = MockRelay(name: "relay 1");
      await relay1.start(events: textNotes.values);

      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.relaySets,
        bootstrapRelays: [relay1.url],
      );
      ndk.accounts.loginPrivateKey(
        pubkey: key1.publicKey,
        privkey: key1.privateKey!,
      );

      final filter = Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key1.publicKey],
      );

      // Using the new single filter parameter
      final query = ndk.requests.query(filter: filter);

      await expectLater(
        query.stream,
        emitsInAnyOrder([textNotes.values.first]),
      );

      await ndk.destroy();
      expect(ndk.relayReqs.openIds.isEmpty, true);
      await relay1.stop();
    });

    test('Request text note', () async {
      MockRelay relay1 = MockRelay(name: "relay 1");
      await relay1.start(events: textNotes.values);

      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.relaySets,
        bootstrapRelays: [relay1.url],
      );
      ndk.accounts.loginPrivateKey(
        pubkey: key1.publicKey,
        privkey: key1.privateKey!,
      );

      final filter = Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key1.publicKey],
      );

      final query = ndk.requests.query(filters: [filter]);

      await expectLater(
        query.stream,
        emitsInAnyOrder([textNotes.values.first]),
      );

      await ndk.destroy();
      expect(ndk.relayReqs.openIds.isEmpty, true);
      await relay1.stop();
    });

    test(
      'Query persists multiple source relays for the same cached event',
      () async {
        final sharedEvent = textNotes.values.first;
        final relay1 = MockRelay(name: "relay 1");
        final relay2 = MockRelay(name: "relay 2");
        await relay1.start(events: [sharedEvent]);
        await relay2.start(events: [sharedEvent]);

        final cache = MemCacheManager();
        final ndk = RequestsClient(
          eventVerifier: MockEventVerifier(),
          cache: cache,
          engine: Engine.relaySets,
          bootstrapRelays: [relay1.url, relay2.url],
        );
        ndk.accounts.loginPrivateKey(
          pubkey: key1.publicKey,
          privkey: key1.privateKey!,
        );

        final filter = Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        );

        final events = await ndk.requests
            .query(filter: filter, explicitRelays: [relay1.url, relay2.url])
            .future;

        expect(events, isNotEmpty);
        final eventId = events.first.id;
        final sources = await cache.loadEventSources(eventId);
        expect(sources, containsAll([relay1.url, relay2.url]));
        expect(sources.length, equals(2));

        await ndk.destroy();
        expect(ndk.relayReqs.openIds.isEmpty, true);
        await relay1.stop();
        await relay2.stop();
      },
    );

    test('Request multiple filters text note', () async {
      MockRelay relay1 = MockRelay(name: "relay 1");
      await relay1.start(events: textNotes.values);

      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.relaySets,
        bootstrapRelays: [relay1.url],
      );
      ndk.accounts.loginPrivateKey(
        pubkey: key1.publicKey,
        privkey: key1.privateKey!,
      );

      final query = ndk.requests.query(
        // explicitRelays: [relay1.url],
        filters: [
          Filter(kinds: [Nip01Event.kTextNoteKind], authors: [key1.publicKey]),
          Filter(kinds: [Nip01Event.kTextNoteKind], authors: [key2.publicKey]),
        ],
      );

      await expectLater(query.stream, emitsInAnyOrder(textNotes.values));

      // await for (final event in query.stream) {
      //   print(event);
      // }

      await ndk.destroy();
      expect(ndk.relayReqs.openIds.isEmpty, true);
      await relay1.stop();
    });
    test('Request multiple filters text note JIT', skip: true, () async {
      MockRelay relay1 = MockRelay(name: "relay 1");
      await relay1.start(events: textNotes.values);

      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.jit,
        bootstrapRelays: [relay1.url],
      );
      ndk.accounts.loginPrivateKey(
        pubkey: key1.publicKey,
        privkey: key1.privateKey!,
      );

      final query = ndk.requests.query(
        // explicitRelays: [relay1.url],
        filters: [
          Filter(kinds: [Nip01Event.kTextNoteKind], authors: [key1.publicKey]),
          Filter(kinds: [Nip01Event.kTextNoteKind], authors: [key2.publicKey]),
        ],
      );

      await expectLater(query.stream, emitsInAnyOrder(textNotes.values));

      // await for (final event in query.stream) {
      //   print(event);
      // }

      await ndk.destroy();
      expect(ndk.relayReqs.openIds.isEmpty, true);
      await relay1.stop();
    });

    test('Subscription with single filter parameter', () async {
      MockRelay relay1 = MockRelay(name: "relay 1");
      await relay1.start(events: textNotes.values);

      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.relaySets,
        bootstrapRelays: [relay1.url],
      );
      ndk.accounts.loginPrivateKey(
        pubkey: key1.publicKey,
        privkey: key1.privateKey!,
      );

      final filter = Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key1.publicKey],
      );

      // Using the new single filter parameter
      final subscription = ndk.requests.subscription(filter: filter);

      final receivedEvents = <Nip01Event>[];
      final streamSubscription = subscription.stream.listen((event) {
        receivedEvents.add(event);
      });
      try {
        await waitForEventCount(receivedEvents, 1);

        expect(receivedEvents.length, equals(1));
        expect(receivedEvents[0].content, contains('key1'));
      } finally {
        await streamSubscription.cancel();
        await ndk.requests.closeSubscription(subscription.requestId);
        await ndk.destroy();
        expect(ndk.relayReqs.openIds.isEmpty, true);
        await relay1.stop();
      }
    });

    test(
      'Subscription processes events immediately without stream closing',
      () async {
        // This test would FAIL with the previous VerifyEventStream implementation
        // because events would remain stuck in buffer until stream closes
        MockRelay relay1 = MockRelay(name: "relay 1");
        await relay1.start(events: textNotes.values);

        final ndk = RequestsClient(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          engine: Engine.relaySets,
          bootstrapRelays: [relay1.url],
        );
        ndk.accounts.loginPrivateKey(
          pubkey: key1.publicKey,
          privkey: key1.privateKey!,
        );

        final filter = Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        );

        // Use subscription instead of query - this creates a long-lived stream
        final subscription = ndk.requests.subscription(filters: [filter]);

        final receivedEvents = <Nip01Event>[];
        final streamSubscription = subscription.stream.listen((event) {
          receivedEvents.add(event);
        });
        try {
          await waitForEventCount(receivedEvents, 1);

          expect(
            receivedEvents.length,
            equals(1),
            reason:
                'Subscription should process events immediately without waiting for stream to close',
          );
          expect(receivedEvents[0].content, contains('key1'));
        } finally {
          await streamSubscription.cancel();
          await ndk.requests.closeSubscription(subscription.requestId);
          await ndk.destroy();
          expect(ndk.relayReqs.openIds.isEmpty, true);
          await relay1.stop();
        }
      },
    );

    test(
      'Subscription handles continuous events from non-closing stream',
      () async {
        // This test simulates a real-world scenario where a subscription
        // receives events continuously without the stream ever closing
        MockRelay relay1 = MockRelay(name: "relay 1");

        // Start with multiple events to test continuous processing
        final multipleEvents = {
          key1: textNote(key1),
          key2: textNote(key2),
          key3: textNote(key3),
          key4: textNote(key4),
        };
        await relay1.start(events: multipleEvents.values);

        final ndk = RequestsClient(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          engine: Engine.relaySets,
          bootstrapRelays: [relay1.url],
        );
        ndk.accounts.loginPrivateKey(
          pubkey: key1.publicKey,
          privkey: key1.privateKey!,
        );

        final filter = Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [
            key1.publicKey,
            key2.publicKey,
            key3.publicKey,
            key4.publicKey,
          ],
        );

        final subscription = ndk.requests.subscription(filters: [filter]);

        final receivedEvents = <Nip01Event>[];
        final allReceived = Completer<void>();
        final streamSubscription = subscription.stream.listen((event) {
          receivedEvents.add(event);
          if (receivedEvents.length >= 4 && !allReceived.isCompleted) {
            allReceived.complete();
          }
        });

        try {
          await allReceived.future.timeout(const Duration(seconds: 3));

          expect(
            receivedEvents.length,
            equals(4),
            reason:
                'Subscription should process all matching events immediately',
          );

          // Verify we got events from different authors (showing parallel processing worked)
          final uniqueAuthors = receivedEvents.map((e) => e.pubKey).toSet();
          expect(
            uniqueAuthors.length,
            greaterThan(1),
            reason: 'Should receive events from multiple authors',
          );
        } finally {
          await streamSubscription.cancel();
          await ndk.requests.closeSubscription(subscription.requestId);
          await ndk.destroy();
          expect(ndk.relayReqs.openIds.isEmpty, true);
          await relay1.stop();
        }
      },
    );
  });

  group('immutable filters', () {
    test('Filters are cloned and immutable in query method', () {
      final cache = MemCacheManager();
      final eventVerifier = MockEventVerifier();
      final client = RequestsClient(eventVerifier: eventVerifier, cache: cache);
      addTearDown(client.destroy);

      // Create a Requests instance
      final requests = Requests(
        defaultQueryTimeout: Duration(seconds: 10),
        cacheRead: MockCacheRead(cache),
        cacheManager: cache,
        networkEngine: RelaySetsEngine(bootstrapRelays: const []),
        relayManager: client.relays,
        eventVerifier: eventVerifier,
        eventOutFilters: [],
      );

      // Create an initial filter
      final originalFilter = Filter(kinds: [1], authors: ['author1']);
      final originalFilterSub = Filter(kinds: [1], authors: ['author1Sub']);

      //   query
      requests.query(filters: [originalFilter]);

      expect(originalFilter.authors!.length, equals(1));

      //   subscription
      requests.subscription(filters: [originalFilterSub], cacheRead: true);
      expect(originalFilterSub.authors!.length, equals(1));
    });
  });

  group('request ids', () {
    late RequestsClient ndk;
    final filter = Filter(kinds: [1]);

    RequestsClient createNdk({bool debugMode = false}) => RequestsClient(
      eventVerifier: MockEventVerifier(),
      cache: MemCacheManager(),
      bootstrapRelays: [],
      debugMode: debugMode,
    );

    setUp(() => ndk = createNdk());

    tearDown(() => ndk.destroy());

    test('ids are random hex and never carry the name', () {
      final query = ndk.requests.query(filter: filter, name: 'secret');
      final sub = ndk.requests.subscription(filter: filter, name: 'secret');

      for (final id in [query.requestId, sub.requestId]) {
        expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      }
    });

    test('debugMode ids keep the name, cut to 32 characters', () {
      final debugNdk = createNdk(debugMode: true);
      addTearDown(debugNdk.destroy);
      final name = 'n' * 32;
      final query = debugNdk.requests.query(filter: filter, name: '${name}x');
      final sub = debugNdk.requests.subscription(filter: filter, name: name);

      for (final id in [query.requestId, sub.requestId]) {
        expect(id, matches(RegExp('^$name-[0-9a-f]{16}\$')));
      }
    });

    test('an explicit id must be 1 to 64 characters', () {
      final requests = <NdkResponse Function(String id)>[
        (id) => ndk.requests.query(filter: filter, id: id),
        (id) => ndk.requests.subscription(filter: filter, id: id),
      ];
      for (final (index, request) in requests.indexed) {
        final longest = '$index' * 64;
        expect(() => request(''), throwsArgumentError);
        expect(() => request('i' * 65), throwsArgumentError);
        expect(request(longest).requestId, longest);
      }
    });

    test('an id already in flight is refused', () {
      ndk.requests.subscription(filter: filter, id: 'taken');

      expect(
        () => ndk.requests.query(filter: filter, id: 'taken'),
        throwsStateError,
      );
    });

    test('an explicit query id cannot be combined with paginate', () {
      expect(
        () => ndk.requests.query(filter: filter, id: 'q', paginate: true),
        throwsArgumentError,
      );
    });
  });

  test('Response with FormatException', () async {
    final mockRelay = MockRelay(name: 'test-relay-format-exception', port: 6062)
      ..onMessage = (client, _) {
        client.sendRaw('{"bad_json":,}');
        return true;
      };
    await mockRelay.start();

    final ndk = RequestsClient(eventVerifier: Bip340EventVerifier());
    addTearDown(ndk.destroy);

    final query = ndk.requests.query(
      filters: [
        Filter(kinds: [1], limit: 1),
      ],
      explicitRelays: [mockRelay.url],
    );

    final events = await query.future;
    expect(events, isEmpty);

    await mockRelay.stop();
  });
}

class MockCacheRead extends CacheRead {
  MockCacheRead(super.cacheManager);

  @override
  Future<List<Filter>> resolveUnresolvedFilters({
    required List<Filter> filters,
    required StreamController<Nip01Event> outController,
  }) async {
    for (var filter in filters) {
      filter.authors = [];
    }
    return filters;
  }
}
