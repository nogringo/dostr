import 'dart:async';
import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/relay_manager_parts.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

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

  tearDown(() => manager.dispose());

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

      expect(outcomes[relay.url]!.status, RelayRequestStatus.timedOut);
      await eventually(() => relay.received('CLOSE').isNotEmpty);
    });

    test(
      'gets the default timeout when given none, unlike a subscription',
      () async {
        final relay = await startRelay(answerRequests: false);
        final query = reqs.req(relays: {relay.url: notes});
        final subscription = reqs.req(
          relays: {relay.url: notes},
          closeOnEose: false,
        );
        final inFlight = relayManagerParts(manager).requests.inFlight;

        expect(inFlight[query.id]!.timeoutDuration, defaultQueryTimeout);
        expect(inFlight[subscription.id]!.timeoutDuration, isNull);
        await Future.wait([query.close(), subscription.close()]);
      },
    );

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
        addTearDown(manager.dispose);
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
      addTearDown(manager.dispose);
      final reqs = RelayReqs(relayManager: manager, eventVerifier: verifier);

      final req = reqs.req(
        relays: {
          relay.url: [hundredKilobytes],
        },
      );
      await req.done;

      final sent = jsonEncode(['REQ', req.id, hundredKilobytes.toJson()]);
      expect(learned, [(relay.url, utf8.encode(sent).length - 1)]);
    });

    test('reports a blocked relay as notSent', () async {
      final blocked = RelayUrl.parse('wss://blocked.example');
      await manager.blockRelay(blocked);

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

      final outcome = (await req.done)[nobody]!;
      expect(outcome.status, RelayRequestStatus.notSent);
      expect(outcome.failure?.kind, RelayFailureKind.unreachable);
      expect(outcome.failure?.detail, isNotNull);
    });

    test('sends to a relay it reached, once its socket dropped', () async {
      final manager = newRelayManager(allowReconnect: false);
      addTearDown(manager.dispose);
      final reqs = RelayReqs(relayManager: manager, eventVerifier: verifier);
      final relay = await startRelay();
      final subscription = reqs.req(
        relays: {relay.url: notes},
        closeOnEose: false,
      );
      await eventually(() => subscribed(relay, subscription));

      await relay.dropConnections();
      expect(
        (await subscription.done)[relay.url]?.status,
        RelayRequestStatus.disconnected,
      );

      final req = reqs.req(relays: {relay.url: notes});
      expect(await req.done, {
        relay.url: const RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });
  });

  group('relays', () {
    test('a request without relays ends at once', () async {
      final req = reqs.req(relays: {});

      expect(await req.done, isEmpty);
      expect(await req.events.toList(), isEmpty);
    });

    test('leaves out the filters that match nothing', () async {
      final relay = await startRelay();
      final req = reqs.req(
        relays: {
          relay.url: [Filter(authors: []), ...notes],
        },
      );
      req.events.listen((_) {});

      await req.done;
      expect(relay.received('REQ'), [
        ['REQ', req.id, notes.single.toJson()],
      ]);
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
      final relay = await startRelay(answerRequests: false);
      final req = reqs.req(relays: {relay.url: notes}, id: 'same');

      expect(() => reqs.req(relays: {}, id: 'same'), throwsStateError);
      expect(() => reqs.req(relays: {}, id: ''), throwsArgumentError);
      expect(() => reqs.req(relays: {}, id: 'x' * 65), throwsArgumentError);

      await req.close();
      await reqs.req(relays: {}, id: 'same').done;
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

  group('the events a relay sends', () {
    Future<(MockRelay, RelayReq, List<Nip01Event>)> subscribe(
      RelayReqs reqs, [
      List<Filter>? filters,
    ]) async {
      final relay = await startRelay();
      final req = reqs.req(
        relays: {relay.url: filters ?? notes},
        closeOnEose: false,
      );
      final received = <Nip01Event>[];
      req.events.listen((e) => received.add(e.event));
      await eventually(() => subscribed(relay, req));
      return (relay, req, received);
    }

    void send(MockRelay relay, RelayReq req, Iterable<Nip01Event> events) {
      for (final event in events) {
        relay.sendToAll(['EVENT', req.id, event.toJson()]);
      }
    }

    test('are dropped when they match none of its filters', () async {
      final (relay, req, received) = await subscribe(reqs, [
        Filter(kinds: [1], authors: [alice]),
        Filter(kinds: [7]),
      ]);
      final byBob = signedEvent(pubkey: bob, content: 'not asked for');
      final reaction = signedEvent(pubkey: bob, kind: 7);
      final byAlice = signedEvent(content: 'asked for');

      send(relay, req, [byBob, reaction, byAlice]);
      await eventually(() => received.any((e) => e.id == byAlice.id));

      expect(received.map((e) => e.id), [reaction.id, byAlice.id]);
      await req.close();
    });

    test('come in the order it sent them, whatever their verification '
        'takes', () async {
      final slow = signedEvent(content: 'slow');
      final fast = signedEvent(content: 'fast');
      final verifier = _ScriptedVerifier(held: {slow.id});
      final (relay, req, received) = await subscribe(
        RelayReqs(relayManager: manager, eventVerifier: verifier),
      );

      send(relay, req, [slow, fast]);
      await eventually(() => verifier.verifying.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, isEmpty);

      verifier.release.complete();
      await eventually(() => received.length == 2);
      expect(received.map((e) => e.id), [slow.id, fast.id]);
      await req.close();
    });

    test('are dropped when their verifier throws, and the next ones still '
        'come', () async {
      final failing = signedEvent(content: 'failing');
      final next = signedEvent(content: 'next');
      final (relay, req, received) = await subscribe(
        RelayReqs(
          relayManager: manager,
          eventVerifier: _ScriptedVerifier(throwing: {failing.id}),
        ),
      );

      send(relay, req, [failing, next]);
      await eventually(() => received.isNotEmpty);

      expect(received.map((e) => e.id), [next.id]);
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
    });
  }

  test('sends its CLOSE once, however often it is closed', () async {
    final relay = await startRelay();
    final req = reqs.req(relays: {relay.url: notes}, closeOnEose: false);
    await eventually(() => subscribed(relay, req));

    await Future.wait([req.close(), req.close()]);

    await req.done;
    await eventually(() => !subscribed(relay, req));
    expect(relay.received('CLOSE'), [
      ['CLOSE', req.id],
    ]);
  });
}

/// Accepts [fakeSig], once [release] completes for the events in [held], and
/// throws for those in [throwing].
class _ScriptedVerifier implements EventVerifier {
  _ScriptedVerifier({this.held = const {}, this.throwing = const {}});

  final Set<String> held;
  final Set<String> throwing;
  final release = Completer<void>();
  final verifying = <String>[];

  @override
  Future<bool> verify(Nip01Event event) async {
    verifying.add(event.id);
    if (held.contains(event.id)) await release.future;
    if (throwing.contains(event.id)) throw StateError('verifier bug');
    return event.sig == fakeSig;
  }
}
