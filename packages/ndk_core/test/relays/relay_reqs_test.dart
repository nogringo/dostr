import 'dart:async';

import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';
import '../mocks/mock_relay.dart';

void main() {
  late RelayManager manager;
  late FakeVerifier verifier;
  late RelayReqs reqs;

  final notes = [
    Filter(kinds: [1]),
  ];

  setUp(() {
    manager = newRelayManager();
    verifier = FakeVerifier();
    reqs = RelayReqs(relayManager: manager, eventVerifier: verifier);
  });

  tearDown(() => manager.closeAllTransports());

  bool subscribed(MockRelay relay, RelayReq req) =>
      relay.openClients.any((c) => c.subscriptions.containsKey(req.id));

  group('query', () {
    test('returns the matching events, tagged with their relay', () async {
      final relay = await startRelay();
      final note = signedEvent(content: 'hello', createdAt: 1000);
      relay.events
        ..add(note)
        ..add(signedEvent(kind: 7, createdAt: 1001));

      final req = reqs.req(relays: {relay.url: notes});
      final events = await req.events.toList();

      expect(events.map((e) => e.id), [note.id]);
      // ignore: deprecated_member_use_from_same_package
      expect(events.single.sources, [relay.url]);
      expect(await req.done, {
        relay.url: const RelayRequestOutcome(RelayRequestStatus.eose),
      });
      await eventually(() => relay.received('CLOSE').isNotEmpty);
      expect(relay.received('CLOSE'), [
        ['CLOSE', req.id],
      ]);
    });

    test('delivers an event once per relay and verifies it once', () async {
      final first = await startRelay();
      final second = await startRelay();
      final note = signedEvent(createdAt: 1000);
      first.events.add(note);
      second.events.add(note);

      final events = await reqs
          .req(relays: {first.url: notes, second.url: notes})
          .events
          .toList();

      expect(events.map((e) => e.id), [note.id, note.id]);
      expect(
        // ignore: deprecated_member_use_from_same_package
        events.map((e) => e.sources.single),
        unorderedEquals([first.url, second.url]),
      );
      expect(verifier.verifications, 1);
    });

    test('drops events whose signature or id does not hold', () async {
      final relay = await startRelay();
      relay.events.addAll([
        signedEvent(content: 'good', createdAt: 1),
        signedEvent(content: 'forged', createdAt: 2).copyWith(sig: 'e' * 128),
        signedEvent(
          content: 'original',
          createdAt: 3,
        ).copyWith(content: 'tampered'),
      ]);

      final events = await reqs.req(relays: {relay.url: notes}).events.toList();

      expect(events.map((e) => e.content), ['good']);
    });

    test('ends on its timeout when a relay never answers', () async {
      final relay = await startRelay(answerRequests: false);

      final req = reqs.req(
        relays: {relay.url: notes},
        timeout: const Duration(milliseconds: 500),
      );
      final outcomes = await req.done;

      expect(req.timedOut, isTrue);
      expect(outcomes[relay.url]!.status, RelayRequestStatus.timedOut);
      await eventually(() => relay.received('CLOSE').isNotEmpty);
    });

    test('reports a blocked relay as notSent', () async {
      const blocked = 'wss://blocked.example';
      manager.blockedRelays.add(blocked);

      final req = reqs.req(relays: {blocked: notes});

      expect(await req.events.toList(), isEmpty);
      expect(await req.done, {
        blocked: const RelayRequestOutcome(
          RelayRequestStatus.notSent,
          message: 'relay is blocked',
        ),
      });
    });
  });

  group('send and seal', () {
    test('a request without relays is held open until sealed', () async {
      final relay = await startRelay();
      relay.events.add(signedEvent(createdAt: 1));
      final req = reqs.req();
      final events = req.events.toList();
      var ended = false;
      unawaited(req.done.then((_) => ended = true));

      expect(req.send(relay.url, notes), isTrue);
      await eventually(
        () => req.outcomes[relay.url]?.status == RelayRequestStatus.eose,
      );
      await pumpEventQueue();
      expect(ended, isFalse);

      req.seal();
      await req.done;
      expect(await events, hasLength(1));
      expect(req.send(relay.url, notes), isFalse);
    });

    test('sends to each relay once', () async {
      final relay = await startRelay();
      final req = reqs.req();
      req.events.listen((_) {});

      req.send(relay.url, notes);

      expect(() => req.send('${relay.url}/', notes), throwsStateError);
      await req.close();
    });

    test('takes a free id that relays accept', () async {
      final req = reqs.req(id: 'same');

      expect(() => reqs.req(id: 'same'), throwsStateError);
      expect(() => reqs.req(id: ''), throwsArgumentError);
      expect(() => reqs.req(id: 'x' * 65), throwsArgumentError);

      await req.close();
      await reqs.req(id: 'same').close();
    });
  });

  group('subscription', () {
    test('streams new events until closed, then sends CLOSE', () async {
      final relay = await startRelay();
      final req = reqs.req(relays: {relay.url: notes}, closeOnEose: false);
      final received = <Nip01Event>[];
      req.events.listen(received.add);
      await eventually(() => subscribed(relay, req));

      final live = signedEvent(content: 'live');
      await RelayPublishes(
        relayManager: manager,
      ).publish(live, relays: [relay.url]).broadcastDoneFuture;
      await eventually(() => received.isNotEmpty);
      expect(received.single.id, live.id);

      await req.close();
      expect(await req.done, contains(relay.url));
      await eventually(() => !subscribed(relay, req));
      expect(relay.received('CLOSE'), [
        ['CLOSE', req.id],
      ]);
    });

    test('reports the relays that caught up and stays open', () async {
      final caughtUp = await startRelay();
      final silent = await startRelay(answerRequests: false);
      final req = reqs.req(
        relays: {caughtUp.url: notes, silent.url: notes},
        closeOnEose: false,
      );
      final received = <Nip01Event>[];
      req.events.listen(received.add);

      await eventually(
        () => req.outcomes[caughtUp.url]?.status == RelayRequestStatus.eose,
      );
      expect(req.outcomes[silent.url]?.status, RelayRequestStatus.pending);
      expect(caughtUp.received('CLOSE'), isEmpty);

      final live = signedEvent(content: 'after the eose');
      caughtUp.sendToAll([
        'EVENT',
        req.id,
        Nip01EventModel.fromEntity(live).toJson(),
      ]);
      await eventually(() => received.any((e) => e.id == live.id));
      expect(reqs.openIds, [req.id]);
      await req.close();
    });

    test('cancelling its events closes the request', () async {
      final relay = await startRelay();
      final req = reqs.req(relays: {relay.url: notes}, closeOnEose: false);
      final subscription = req.events.listen((_) {});
      await eventually(() => subscribed(relay, req));

      await subscription.cancel();

      await req.done;
      await eventually(() => !subscribed(relay, req));
      expect(reqs.openIds, isEmpty);
    });

    test('is sent again once the relay drops the connection', () async {
      final relay = await startRelay();
      final req = reqs.req(relays: {relay.url: notes}, closeOnEose: false);
      final received = <Nip01Event>[];
      req.events.listen(received.add);
      await eventually(() => subscribed(relay, req));

      await relay.dropConnections();
      await eventually(
        () => subscribed(relay, req),
        timeout: const Duration(seconds: 10),
      );
      expect(relay.clients, hasLength(2));

      final live = signedEvent(content: 'after the drop');
      relay.sendToAll([
        'EVENT',
        req.id,
        Nip01EventModel.fromEntity(live).toJson(),
      ]);
      await eventually(() => received.any((e) => e.id == live.id));
      await req.close();
    });
  });

  group('close by id', () {
    test('closes a REQ another RelayReqs opened, once', () async {
      final relay = await startRelay();
      final req = reqs.req(relays: {relay.url: notes}, closeOnEose: false);
      await eventually(() => subscribed(relay, req));
      final others = RelayReqs(relayManager: manager, eventVerifier: verifier);

      final closed = others.close(req.id);
      await req.close();

      expect(await closed, isTrue);
      await req.done;
      await eventually(() => !subscribed(relay, req));
      expect(relay.received('CLOSE'), [
        ['CLOSE', req.id],
      ]);
      expect(await others.close(req.id), isFalse);
    });

    test('closeAll closes the REQs of every RelayReqs', () async {
      final relay = await startRelay();
      final others = RelayReqs(relayManager: manager, eventVerifier: verifier);
      final first = reqs.req(relays: {relay.url: notes}, closeOnEose: false);
      final second = others.req(relays: {relay.url: notes}, closeOnEose: false);
      await eventually(
        () => subscribed(relay, first) && subscribed(relay, second),
      );

      await reqs.closeAll();

      await Future.wait([first.done, second.done]);
      await eventually(
        () => !subscribed(relay, first) && !subscribed(relay, second),
      );
      expect(await reqs.close(first.id), isFalse);
      expect(await reqs.close(second.id), isFalse);
    });
  });
}
