import 'dart:async';
import 'dart:convert';

import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';

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

  final hundredKilobytes = Filter(
    authors: [
      for (var i = 0; i < 1600; i++) i.toRadixString(16).padLeft(64, '0'),
    ],
  );

  group('query', () {
    test('returns the matching events, tagged with their relay', () async {
      final relay = await startRelay();
      final note = signedEvent(content: 'hello', createdAt: 1000);
      relay.events
        ..add(note)
        ..add(signedEvent(kind: 7, createdAt: 1001));

      final req = reqs.req(relays: {relay.url: notes});
      final events = await req.events.toList();

      expect(events.map((e) => e.event.id), [note.id]);
      expect(events.single.relayUrl, relay.url);
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

      expect(events.map((e) => e.event.id), [note.id, note.id]);
      expect(
        events.map((e) => e.relayUrl),
        unorderedEquals([first.url, second.url]),
      );
      expect(verifier.verifications, 1);
    });

    test('drops events whose signature or id does not hold', () async {
      final relay = await startRelay();
      final original = signedEvent(content: 'original', createdAt: 3);
      relay.events.addAll([
        signedEvent(content: 'good', createdAt: 1),
        signedEvent(content: 'forged', createdAt: 2).copyWith(sig: 'e' * 128),
        original.copyWith(id: original.id, content: 'tampered'),
      ]);

      final events = await reqs.req(relays: {relay.url: notes}).events.toList();

      expect(events.map((e) => e.event.content), ['good']);
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

    test('a 100 KB filter sent to a relay that accepts 64 KB ends the query '
        'instead of being sent again', () async {
      final relay = await startRelay(maxMessageLength: 64 * 1024);

      final req = reqs.req(
        relays: {
          relay.url: [hundredKilobytes],
        },
        timeout: const Duration(seconds: 2),
      );
      final outcome = (await req.done)[relay.url]!;

      expect(relay.oversizedMessages, 1);
      expect(outcome.status, RelayRequestStatus.notSent);
      expect(outcome.failure?.kind, RelayFailureKind.messageTooLong);
    });

    test(
      'a filter longer than the relay says it reads is never sent',
      () async {
        final relay = await startRelay(maxMessageLength: 64 * 1024);
        final manager = newRelayManager(messageLengthLimit: (_) => 64 * 1024);
        addTearDown(manager.closeAllTransports);
        final reqs = RelayReqs(relayManager: manager, eventVerifier: verifier);

        final req = reqs.req(
          relays: {
            relay.url: [hundredKilobytes],
          },
        );
        final outcome = (await req.done)[relay.url]!;

        expect(outcome.status, RelayRequestStatus.notSent);
        expect(outcome.failure?.kind, RelayFailureKind.messageTooLong);
        expect(relay.oversizedMessages, 0);
        expect(relay.clients, hasLength(1));
      },
    );

    test(
      'the REQs a 1009 cut off go out again, but not the one too long',
      () async {
        final relay = await startRelay(maxMessageLength: 64 * 1024);
        final subscription = reqs.req(
          relays: {relay.url: notes},
          closeOnEose: false,
        );
        await eventually(() => subscribed(relay, subscription));

        final query = reqs.req(
          relays: {
            relay.url: [hundredKilobytes],
          },
        );

        expect(
          (await query.done)[relay.url]!.failure?.kind,
          RelayFailureKind.messageTooLong,
        );
        await eventually(() => subscribed(relay, subscription));
        expect(relay.clients, hasLength(2));
        expect(relay.oversizedMessages, 1);
        await subscription.close();
      },
    );

    test('a limit learned from a 1009 is handed out to be kept', () async {
      final relay = await startRelay(maxMessageLength: 64 * 1024);
      final learned = <(String, int)>[];
      final manager = newRelayManager(
        onMessageLengthLearned: (url, length) => learned.add((url, length)),
      );
      addTearDown(manager.closeAllTransports);
      final reqs = RelayReqs(relayManager: manager, eventVerifier: verifier);

      final req = reqs.req(
        relays: {
          relay.url: [hundredKilobytes],
        },
      );
      await req.done;

      final sent = jsonEncode(['REQ', req.id, hundredKilobytes.toMap()]);
      expect(learned, [(relay.url, utf8.encode(sent).length - 1)]);
    });

    test('reports a blocked relay as notSent', () async {
      const blocked = 'wss://blocked.example';
      manager.blockedRelays.add(blocked);

      final req = reqs.req(relays: {blocked: notes});

      expect(await req.events.toList(), isEmpty);
      expect(await req.done, {
        blocked: const RelayRequestOutcome(
          RelayRequestStatus.notSent,
          failure: RelayFailure(RelayFailureKind.blocked),
        ),
      });
    });
    test('reports a relay nothing listens on as notSent', () async {
      final nobody = MockRelay().url;

      final req = reqs.req(relays: {nobody: notes});

      expect(await req.done, {
        nobody: const RelayRequestOutcome(
          RelayRequestStatus.notSent,
          failure: RelayFailure(RelayFailureKind.unreachable),
        ),
      });
    });
  });

  group('send and seal', () {
    test('a request sealed without relays ends at once', () async {
      final req = reqs.req(relays: {});

      expect(await req.done, isEmpty);
      expect(await req.events.toList(), isEmpty);
    });

    test('takes a relay sent after seal while it is not over', () async {
      final first = await startRelay();
      final second = await startRelay();
      final req = reqs.req();

      expect(req.send(first.url, notes), isTrue);
      req.seal();
      expect(req.send(second.url, notes), isTrue);

      expect(await req.done, {
        first.url: const RelayRequestOutcome(RelayRequestStatus.eose),
        second.url: const RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });

    test('sends nothing once it is over', () async {
      final relay = await startRelay();
      final req = reqs.req(relays: {});
      await req.done;

      expect(req.send(relay.url, notes), isFalse);
      expect(req.outcomes, isEmpty);
    });

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

    test('sends to each relay once, and only to relays', () async {
      final relay = await startRelay();
      final req = reqs.req();
      req.events.listen((_) {});

      expect(req.send(relay.url, notes), isTrue);
      expect(req.send('${relay.url}/', notes), isFalse);
      expect(req.send('https://relay.example', notes), isFalse);

      await eventually(() => relay.received('REQ').isNotEmpty);
      expect(relay.received('REQ'), hasLength(1));
      expect(req.outcomes.keys, [relay.url]);
      await req.close();
    });

    test('leaves out the filters that match nothing', () async {
      final relay = await startRelay();
      final req = reqs.req();
      req.events.listen((_) {});

      expect(req.send(relay.url, [Filter(authors: [])]), isFalse);
      expect(req.send(relay.url, [Filter(authors: []), ...notes]), isTrue);

      await eventually(() => relay.received('REQ').isNotEmpty);
      expect(relay.received('REQ'), [
        ['REQ', req.id, notes.single.toMap()],
      ]);
      await req.close();
    });

    test('a request whose filters all match nothing ends at once', () async {
      final relay = await startRelay();
      final req = reqs.req(
        relays: {
          relay.url: [Filter(ids: [])],
        },
      );

      expect(await req.events.toList(), isEmpty);
      expect(await req.done, isEmpty);
      await pumpEventQueue();
      expect(relay.received('REQ'), isEmpty);
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
      req.events.listen((e) => received.add(e.event));
      await eventually(() => subscribed(relay, req));

      final live = signedEvent(content: 'live');
      await RelayPublishes(
        relayManager: manager,
      ).publish(live, relays: [relay.url]).done;
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
      req.events.listen((e) => received.add(e.event));

      await eventually(
        () => req.outcomes[caughtUp.url]?.status == RelayRequestStatus.eose,
      );
      expect(req.outcomes[silent.url]?.status, RelayRequestStatus.pending);
      expect(caughtUp.received('CLOSE'), isEmpty);

      final live = signedEvent(content: 'after the eose');
      caughtUp.sendToAll(['EVENT', req.id, live.toJson()]);
      await eventually(() => received.any((e) => e.id == live.id));
      expect(reqs.openIds, [req.id]);
      await req.close();
    });

    test('a CLOSED from one relay leaves the others serving it', () async {
      final closing = await startRelay();
      final serving = await startRelay();
      final req = reqs.req(
        relays: {closing.url: notes, serving.url: notes},
        closeOnEose: false,
      );
      final received = <Nip01Event>[];
      req.events.listen((e) => received.add(e.event));
      await eventually(
        () => subscribed(closing, req) && subscribed(serving, req),
      );

      closing.sendToAll(['CLOSED', req.id, 'rate limited']);

      await eventually(
        () => req.outcomes[closing.url]?.status == RelayRequestStatus.closed,
      );
      expect(
        req.outcomes[serving.url]?.status,
        isNot(RelayRequestStatus.closed),
      );
      expect(reqs.openIds, [req.id]);
      final live = signedEvent(content: 'from the relay still serving it');
      serving.sendToAll(['EVENT', req.id, live.toJson()]);
      await eventually(() => received.any((e) => e.id == live.id));
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
      req.events.listen((e) => received.add(e.event));
      await eventually(() => subscribed(relay, req));

      await relay.dropConnections();
      await eventually(
        () => subscribed(relay, req),
        timeout: const Duration(seconds: 10),
      );
      expect(relay.clients, hasLength(2));

      final live = signedEvent(content: 'after the drop');
      relay.sendToAll(['EVENT', req.id, live.toJson()]);
      await eventually(() => received.any((e) => e.id == live.id));
      await req.close();
    });
  });

  for (final closeOnEose in [true, false]) {
    test('a ${closeOnEose ? 'query' : 'subscription'} ends as disconnected '
        'once its connection is closed', () async {
      final relay = await startRelay(answerRequests: false);
      final req = reqs.req(
        relays: {relay.url: notes},
        closeOnEose: closeOnEose,
      );
      await eventually(() => subscribed(relay, req));

      await manager.closeConnectionsTo(relay.url);

      expect(await req.done, {
        relay.url: const RelayRequestOutcome(RelayRequestStatus.disconnected),
      });
      expect(reqs.openIds, isEmpty);
    });
  }

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
