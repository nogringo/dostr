import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  late RelayManager manager;
  late RelayPublishes publishes;

  setUp(() {
    manager = newRelayManager();
    publishes = RelayPublishes(relayManager: manager);
  });

  tearDown(() => manager.dispose());

  (String, bool, bool, String) summary(
    MapEntry<RelayUrl, RelayPublishOutcome> response,
  ) => (
    response.key,
    response.value.okReceived,
    response.value.accepted,
    response.value.message,
  );

  test('collects the OK of every relay', () async {
    final first = await startRelay();
    final second = await startRelay();
    final event = signedEvent(content: 'hello');

    final responses = await publishes
        .publish(event, relays: [first.url, second.url])
        .done;

    expect(
      responses.entries.map(summary),
      unorderedEquals([
        (first.url, true, true, ''),
        (second.url, true, true, ''),
      ]),
    );
    expect(first.events.single.id, event.id);
    expect(second.events.single.id, event.id);
  });

  test('reports why a relay refused the event', () async {
    final relay = await startRelay(rejectEventsWith: 'blocked: spam');

    final responses = await publishes
        .publish(signedEvent(), relays: [relay.url])
        .done;

    expect(responses.entries.map(summary), [
      (relay.url, true, false, 'blocked: spam'),
    ]);
  });

  test('fails a relay it cannot connect to', () async {
    final blocked = RelayUrl.parse('wss://blocked.example');
    await manager.blockRelay(blocked);

    final responses = await publishes
        .publish(signedEvent(), relays: [blocked])
        .done;

    expect(responses.entries.map(summary), [(blocked, false, false, '')]);
    expect(
      responses.values.single.failure,
      const RelayFailure(RelayFailureKind.blocked),
    );
  });

  test('fails a relay nothing listens on as unreachable', () async {
    final nobody = MockRelay().url;

    final responses = await publishes
        .publish(signedEvent(), relays: [nobody])
        .done;

    expect(responses[nobody]!.accepted, isFalse);
    expect(responses[nobody]!.failure?.kind, RelayFailureKind.unreachable);
  });

  test('fails a relay when the identity it requires cannot sign', () async {
    final relay = await startRelay();

    final responses = await publishes
        .publish(
          signedEvent(),
          relays: [relay.url],
          auth: AuthPolicy.require(fakeAccount(alice, canSign: false)),
        )
        .done;

    expect(
      responses.values.single.failure,
      const RelayFailure(RelayFailureKind.cannotSign),
    );
    expect(relay.events, isEmpty);
  });

  group('an EVENT a relay took without answering', () {
    Future<(MockRelay, Nip01Event, RelayPublish)> unanswered() async {
      final relay = await startRelay(answerEvents: false);
      final event = signedEvent(content: 'no OK yet');
      final publish = publishes.publish(
        event,
        relays: [relay.url],
        timeout: const Duration(seconds: 30),
      );
      await eventually(() => relay.received('EVENT').isNotEmpty);
      return (relay, event, publish);
    }

    test('fails as connectionLost when its connection is closed', () async {
      final (relay, _, publish) = await unanswered();

      await manager.closeConnectionsTo(relay.url);

      final outcome = (await publish.done)[relay.url]!;
      expect(outcome.failure?.kind, RelayFailureKind.connectionLost);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('fails as connectionLost when its socket drops for good', () async {
      final (relay, _, publish) = await unanswered();
      manager.allowReconnectRelays = false;

      await relay.dropConnections();

      final outcome = (await publish.done)[relay.url]!;
      expect(outcome.failure?.kind, RelayFailureKind.connectionLost);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('goes out again once its socket is back', () async {
      final (relay, event, publish) = await unanswered();
      relay.answerEvents = true;

      await relay.dropConnections();

      final outcome = (await publish.done)[relay.url]!;
      expect(outcome.accepted, isTrue);
      expect(relay.receivedEvents.map((e) => e.id), [event.id, event.id]);
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  test('refuses an unsigned event', () {
    final unsigned = Nip01Event(pubkey: alice, kind: 1, tags: [], content: '');

    expect(
      () => publishes.publish(
        unsigned,
        relays: [RelayUrl.parse('wss://relay.example')],
      ),
      throwsArgumentError,
    );
  });

  test('refuses a considerDoneRatio outside 0 to 1', () {
    for (final ratio in [-0.1, 1.5, double.nan]) {
      expect(
        () => publishes.publish(
          signedEvent(),
          relays: [],
          considerDoneRatio: ratio,
        ),
        throwsArgumentError,
      );
    }
  });

  test('is done right away without relays', () async {
    final responses = await publishes
        .publish(signedEvent(), relays: [])
        .done
        .timeout(const Duration(seconds: 2));

    expect(responses, isEmpty);
  });

  test('sends to a relay once, however its url is written', () async {
    final relay = await startRelay();

    await publishes
        .publish(
          signedEvent(),
          relays: [relay.url, RelayUrl.parse('${relay.url}/')],
        )
        .done;

    expect(relay.received('EVENT'), hasLength(1));
  });

  test('concurrent broadcasts of one event each get their OK', () async {
    final relay = await startRelay();
    final event = signedEvent();

    final broadcasts = [
      publishes.publish(event, relays: [relay.url]).done,
      publishes.publish(event, relays: [relay.url]).done,
    ];
    expect(manager.isPublishing(event.id), isTrue);
    final responses = await Future.wait(broadcasts);

    for (final response in responses) {
      expect(response.values.single.accepted, isTrue);
    }
    expect(manager.isPublishing(event.id), isFalse);
  });

  test('is done once enough relays accepted the event', () async {
    final fast = await startRelay();
    final silent = await startRelay(answerEvents: false);

    final responses = await publishes
        .publish(
          signedEvent(),
          relays: [fast.url, silent.url],
          considerDoneRatio: 0.5,
        )
        .done
        .timeout(const Duration(seconds: 3));

    expect(responses.entries.where((r) => r.value.accepted).map((r) => r.key), [
      fast.url,
    ]);
  });

  test('does not count a refusal towards considerDoneRatio', () async {
    final refusing = await startRelay(rejectEventsWith: 'blocked: no');
    final silent = await startRelay(answerEvents: false);
    final publish = publishes.publish(
      signedEvent(),
      relays: [refusing.url, silent.url],
      considerDoneRatio: 0.5,
      timeout: const Duration(milliseconds: 500),
    );
    var done = false;
    unawaited(publish.done.then((_) => done = true));

    await eventually(() => publish.outcomes[refusing.url]!.okReceived);
    await pumpEventQueue();
    expect(done, isFalse, reason: 'the refusal made it look half done');

    final responses = await publish.done;
    expect(responses[refusing.url]!.accepted, isFalse);
    expect(responses[silent.url]!.okReceived, isFalse);
  });

  test('ends on its timeout when a relay never answers', () async {
    final silent = await startRelay(answerEvents: false);

    final responses = await publishes
        .publish(
          signedEvent(),
          relays: [silent.url],
          timeout: const Duration(milliseconds: 500),
        )
        .done;

    expect(responses.values.single.okReceived, isFalse);
    expect(silent.events, hasLength(1));
  });

  test(
    'fails a relay that reads less than the event, without sending it',
    () async {
      final relay = await startRelay();
      final manager = newRelayManager(
        messageLengthLimit: (_) =>
            Future.delayed(const Duration(milliseconds: 100), () => 1000),
      );
      addTearDown(manager.dispose);

      final responses = await RelayPublishes(
        relayManager: manager,
      ).publish(signedEvent(content: 'x' * 1000), relays: [relay.url]).done;

      expect(
        responses.values.single.failure?.kind,
        RelayFailureKind.messageTooLong,
      );
      expect(relay.received('EVENT'), isEmpty);
    },
  );

  group('open', () {
    test('is in flight before it is signed', () async {
      final relay = await startRelay();
      final event = signedEvent();
      final unsigned = Nip01Event(
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
      );

      final publish = publishes.open(unsigned);
      expect(manager.isPublishing(event.id), isTrue);

      publish.start(event);
      expect(publish.send(relay.url), isTrue);
      publish.seal();
      final responses = await publish.done;

      expect(responses.values.single.accepted, isTrue);
      expect(relay.events.single.sig, event.sig);
      expect(manager.isPublishing(event.id), isFalse);
    });

    test('takes a relay once sealed only if the publish is not over', () async {
      final first = await startRelay();
      final late = await startRelay();
      final event = signedEvent();
      final publish = publishes.open(event)..start(event);

      publish.send(first.url);
      publish.seal();
      await publish.done;

      expect(publish.send(late.url), isFalse);
      expect(late.received('EVENT'), isEmpty);
    });

    test('sends to a relay once', () async {
      final relay = await startRelay();
      final event = signedEvent();
      final publish = publishes.open(event)..start(event);

      expect(publish.send(relay.url), isTrue);
      expect(publish.send(RelayUrl.parse('${relay.url}/')), isFalse);
      publish.seal();
      await publish.done;

      expect(relay.received('EVENT'), hasLength(1));
      expect(publish.outcomes.keys, [relay.url]);
    });

    test('reports the OK of each relay as it comes', () async {
      final relay = await startRelay();
      final event = signedEvent();
      final publish = publishes.open(event)..start(event);
      final updates = publish.outcomesStream.toList();

      publish.send(relay.url);
      expect(publish.outcomes[relay.url]!.okReceived, isFalse);
      publish.seal();
      final outcomes = await publish.done;

      expect(outcomes[relay.url]!.accepted, isTrue);
      expect(publish.outcomes, outcomes);
      expect((await updates).last[relay.url]!.accepted, isTrue);
    });

    test('cannot be sent before it is started', () {
      final publish = publishes.open(signedEvent());

      expect(
        () => publish.send(RelayUrl.parse('wss://relay.example')),
        throwsStateError,
      );
    });

    test('refuses to start unsigned', () {
      final unsigned = Nip01Event(
        pubkey: alice,
        kind: 1,
        tags: [],
        content: '',
      );
      final publish = publishes.open(unsigned);

      expect(() => publish.start(unsigned), throwsArgumentError);
    });

    test('follows the id of an event its signer changed', () async {
      final relay = await startRelay();
      final asked = signedEvent(content: 'asked');
      final signed = signedEvent(content: 'signed');
      final publish = publishes.open(asked)..start(signed);

      publish.send(relay.url);
      publish.seal();
      expect(manager.isPublishing(asked.id), isTrue);
      final responses = await publish.done;

      expect(relay.events.single.id, signed.id);
      expect(responses.values.single.accepted, isTrue);
      expect(manager.isPublishing(asked.id), isFalse);
      expect(manager.isPublishing(signed.id), isFalse);
    });

    test('fails with the error it is given', () async {
      final event = signedEvent();
      final publish = publishes.open(event);

      publish.fail(StateError('signer refused'));

      await expectLater(publish.done, throwsA(isA<StateError>()));
      expect(manager.isPublishing(event.id), isFalse);
    });
  });
}
