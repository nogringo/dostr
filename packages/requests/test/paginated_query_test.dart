import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';

import 'mocks/requests_client.dart';
import 'mocks/mock_event_verifier.dart';

void main() async {
  late KeyPair key1;
  late MockRelay relay1;
  late RequestsClient ndk;
  late Bip340EventSigner signer;

  setUp(() async {
    key1 = Bip340.generatePrivateKey();

    signer = Bip340EventSigner(
      privateKey: key1.privateKey,
      publicKey: key1.publicKey,
    );

    relay1 = MockRelay(name: "relay 1", port: 6070, maxEventsPerRequest: 2);

    await relay1.start();

    ndk = RequestsClient(
      eventVerifier: MockEventVerifier(),
      cache: MemCacheManager(),
      bootstrapRelays: [relay1.url],
      logLevel: LogLevel.off,
    );

    ndk.accounts.loginExternalSigner(signer: signer);
  });

  tearDown(() async {
    await ndk.destroy();
    await relay1.stop();
  });

  group('Paginated Query', () {
    test('fetches all events across multiple pages', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Create 5 events spread across time
      final timestamps = [now - 4000, now - 3000, now - 2000, now - 1000, now];

      // Publish events to the relay
      for (final ts in timestamps) {
        final event = Nip01Event(
          kind: Nip01Event.kTextNoteKind,
          pubKey: key1.publicKey,
          content: "Event at $ts",
          tags: [],
          createdAt: ts,
        );
        relay1.publish(event);
      }

      final query = ndk.requests.query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        ),
        paginate: true,
      );

      final events = await query.future;

      expect(events.length, equals(5));
    });

    test('respects since parameter', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timestamps = [
        now - 5000,
        now - 4000,
        now - 3000,
        now - 2000,
        now - 1000,
      ];

      // Publish events
      for (final ts in timestamps) {
        final event = Nip01Event(
          kind: Nip01Event.kTextNoteKind,
          pubKey: key1.publicKey,
          content: "Event at $ts",
          tags: [],
          createdAt: ts,
        );
        relay1.publish(event);
      }

      // Query with since that excludes older events
      final query = ndk.requests.query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
          since: now - 3500, // Should only get events from -3000, -2000, -1000
        ),
        paginate: true,
      );

      final events = await query.future;
      // Should return only 3 events (those after since)
      expect(events.length, equals(3));

      // Verify all events are after 'since'
      for (final event in events) {
        expect(event.createdAt, greaterThanOrEqualTo(now - 3500));
      }
    });

    test('respects until parameter', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timestamps = [
        now - 5000,
        now - 4000,
        now - 3000,
        now - 2000,
        now - 1000,
      ];

      // Publish events
      for (final ts in timestamps) {
        final event = Nip01Event(
          kind: Nip01Event.kTextNoteKind,
          pubKey: key1.publicKey,
          content: "Event at $ts",
          tags: [],
          createdAt: ts,
        );
        relay1.publish(event);
      }

      // Query with until that excludes recent events
      final query = ndk.requests.query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
          until: now - 2500, // Should only get events from -5000, -4000, -3000
        ),
        paginate: true,
      );

      final events = await query.future;
      // Should return only 3 events (those before until)
      expect(events.length, equals(3));

      // Verify all events are before 'until'
      for (final event in events) {
        expect(event.createdAt, lessThanOrEqualTo(now - 2500));
      }
    });

    test('handles events with same timestamp', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sameTimestamp = now - 2000;

      // the first page (2 events) cuts the timestamp they share in half
      final timestamps = [now - 4000, sameTimestamp, sameTimestamp, now - 1000];

      // Publish events
      for (int i = 0; i < timestamps.length; i++) {
        final event = Nip01Event(
          kind: Nip01Event.kTextNoteKind,
          pubKey: key1.publicKey,
          content: "Event $i at ${timestamps[i]}",
          tags: [],
          createdAt: timestamps[i],
        );
        relay1.publish(event);
      }

      final query = ndk.requests.query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        ),
        paginate: true,
      );

      final events = await query.future;

      expect(events.length, equals(4));

      // Verify no duplicates
      final ids = events.map((e) => e.id).toSet();
      expect(ids.length, equals(4));
    });

    Future<void> publish(MockRelay relay, int count, {int offset = 0}) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (var i = 0; i < count; i++) {
        relay.publish(
          Nip01Event(
            kind: Nip01Event.kTextNoteKind,
            pubKey: key1.publicKey,
            content: "Event $offset-$i",
            tags: [],
            createdAt: now - offset - i * 1000,
          ),
        );
      }
    }

    test('closing it stops asking for pages', () async {
      // one event per page, each answered late: the query outlives the close
      final slow = MockRelay(name: "slow", maxEventsPerRequest: 1);
      await slow.start(delayResponse: const Duration(milliseconds: 200));
      addTearDown(slow.stop);
      await publish(slow, 8);

      final query = ndk.requests.query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        ),
        explicitRelays: [slow.url],
        paginate: true,
      );
      await query.stream.first;
      await ndk.requests.closeSubscription(query.requestId);

      // the page that was already on its way counts once it got through the
      // relay's delay
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final requested = slow.totalRequestedSubscriptionCount;
      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(slow.totalRequestedSubscriptionCount, requested);
      expect(await query.future, isNotEmpty);
    });

    test('reports its timeout once, however many pages run into it', () async {
      final relays = [
        MockRelay(name: "goes silent 1", maxEventsPerRequest: 1),
        MockRelay(name: "goes silent 2", maxEventsPerRequest: 1),
      ];
      for (final (index, relay) in relays.indexed) {
        await relay.start();
        addTearDown(relay.stop);
        await publish(relay, 2, offset: index * 100);
      }

      var timeouts = 0;
      final query = ndk.requests.query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        ),
        explicitRelays: relays.map((relay) => relay.url),
        timeout: const Duration(milliseconds: 500),
        timeoutCallbackUserFacing: () => timeouts++,
        paginate: true,
      );
      // every page after the first one runs into the timeout, on each relay
      await query.stream.first;
      for (final relay in relays) {
        relay.answerRequests = false;
      }

      await query.future;
      expect(timeouts, 1);
    });

    test('paginates correctly across multiple relays', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final firstEvent = Nip01Event(
        kind: Nip01Event.kTextNoteKind,
        pubKey: key1.publicKey,
        content: "Event at $now",
        tags: [],
        createdAt: now,
      );
      final firstEventSigned = await signer.sign(firstEvent);

      final relay1EventTimeStamp = now - 3000;
      final relay1Event = Nip01Event(
        kind: Nip01Event.kTextNoteKind,
        pubKey: key1.publicKey,
        content: "Event at $relay1EventTimeStamp",
        tags: [],
        createdAt: relay1EventTimeStamp,
      );
      final relay1EventSigned = await signer.sign(relay1Event);

      final middleEventTimeStamp = now - 5000;
      final middleEvent = Nip01Event(
        kind: Nip01Event.kTextNoteKind,
        pubKey: key1.publicKey,
        content: "Event at $middleEventTimeStamp",
        tags: [],
        createdAt: middleEventTimeStamp,
      );
      final middleEventSigned = await signer.sign(middleEvent);

      final relay2EventTimeStamp = now - 7000;
      final relay2Event = Nip01Event(
        kind: Nip01Event.kTextNoteKind,
        pubKey: key1.publicKey,
        content: "Event at $relay2EventTimeStamp",
        tags: [],
        createdAt: relay2EventTimeStamp,
      );
      final relay2EventSigned = await signer.sign(relay2Event);

      final lastEventTimeStamp = now - 10000;
      final lastEvent = Nip01Event(
        kind: Nip01Event.kTextNoteKind,
        pubKey: key1.publicKey,
        content: "Event at $lastEventTimeStamp",
        tags: [],
        createdAt: lastEventTimeStamp,
      );
      final lastEventSigned = await signer.sign(lastEvent);

      final relay1Events = [
        firstEventSigned,
        relay1EventSigned,
        middleEventSigned,
        lastEventSigned,
      ];
      final relay2Events = [
        firstEventSigned,
        relay2EventSigned,
        lastEventSigned,
      ];

      // Create a second relay
      final relay2 = MockRelay(name: "relay 2", port: 6071);
      await relay2.start();

      try {
        for (final event in relay1Events) {
          relay1.publish(event);
        }

        for (final event in relay2Events) {
          relay2.publish(event);
        }
      } finally {}

      // Query both relays with pagination
      final query = ndk.requests.query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        ),
        explicitRelays: [relay1.url, relay2.url],
        paginate: true,
      );

      final events = await query.future;

      expect(events.length, equals(5));

      await relay2.stop();
    });

    test('paginates each relay of a relay set independently', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // relay 1 holds more history than a page can carry, relay 2 a single much
      // older event, so a page bound to the whole set would drag relay 1 past
      // the events it has left
      final relay1Timestamps = [
        now,
        now - 1000,
        now - 2000,
        now - 3000,
        now - 4000,
      ];
      final relay2Timestamps = [now, now - 9000];

      Future<Nip01Event> signedEventAt(int createdAt) async => signer.sign(
        Nip01Event(
          kind: Nip01Event.kTextNoteKind,
          pubKey: key1.publicKey,
          content: "Event at $createdAt",
          tags: [],
          createdAt: createdAt,
        ),
      );

      final relay2 = MockRelay(
        name: "relay 2",
        port: 6072,
        maxEventsPerRequest: 2,
      );
      await relay2.start();

      try {
        for (final ts in relay1Timestamps) {
          relay1.publish(await signedEventAt(ts));
        }

        for (final ts in relay2Timestamps) {
          relay2.publish(await signedEventAt(ts));
        }

        final relaySet = RelaySet(
          name: "pagination",
          pubKey: key1.publicKey,
          relaysMap: {relay1.url: [], relay2.url: []},
          direction: RelayDirection.outbox,
          fallbackToBootstrapRelays: false,
        );

        final query = ndk.requests.query(
          filter: Filter(
            kinds: [Nip01Event.kTextNoteKind],
            authors: [key1.publicKey],
          ),
          relaySet: relaySet,
          paginate: true,
        );

        final events = await query.future;

        final createdAt = events.map((e) => e.createdAt).toSet();
        expect(createdAt, equals({...relay1Timestamps, ...relay2Timestamps}));
      } finally {
        await relay2.stop();
      }
    });
  });
}
