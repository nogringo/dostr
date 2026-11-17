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

  (String, RelayPublishStatus, String) summary(
    MapEntry<RelayUrl, RelayPublishOutcome> response,
  ) => (response.key, response.value.status, response.value.message);

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
        (first.url, RelayPublishStatus.accepted, ''),
        (second.url, RelayPublishStatus.accepted, ''),
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
      (relay.url, RelayPublishStatus.refused, 'blocked: spam'),
    ]);
  });

  test('fails a relay it cannot connect to', () async {
    final blocked = RelayUrl.parse('wss://blocked.example');
    await manager.blockRelay(blocked);

    final responses = await publishes
        .publish(signedEvent(), relays: [blocked])
        .done;

    expect(responses.entries.map(summary), [
      (blocked, RelayPublishStatus.failed, ''),
    ]);
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
    Future<(MockRelay, Nip01Event, RelayPublish)> unanswered({
      RelayPublishes? on,
    }) async {
      final relay = await startRelay(answerEvents: false);
      final event = signedEvent(content: 'no OK yet');
      final publish = (on ?? publishes).publish(
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
      final manager = newRelayManager(allowReconnect: false);
      addTearDown(manager.dispose);
      final (relay, _, publish) = await unanswered(
        on: RelayPublishes(relayManager: manager),
      );

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
    final responses = await Future.wait(broadcasts);

    for (final response in responses) {
      expect(response.values.single.accepted, isTrue);
    }
  });

  test('reports the OK of each relay as it comes', () async {
    final relay = await startRelay();
    final publish = publishes.publish(signedEvent(), relays: [relay.url]);
    final updates = publish.outcomesStream.toList();

    expect(publish.outcomes[relay.url]!.isPending, isTrue);
    final outcomes = await publish.done;

    expect(outcomes[relay.url]!.accepted, isTrue);
    expect(publish.outcomes, outcomes);
    expect((await updates).last[relay.url]!.accepted, isTrue);
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

    expect(responses.values.single, const RelayPublishOutcome.timedOut());
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
}
