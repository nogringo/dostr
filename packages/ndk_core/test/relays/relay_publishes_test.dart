import 'dart:async';

import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  late RelayManager manager;
  late RelayPublishes publishes;

  setUp(() {
    manager = newRelayManager();
    publishes = RelayPublishes(relayManager: manager);
  });

  tearDown(() => manager.closeAllTransports());

  (String, bool, bool, String) summary(RelayBroadcastResponse response) => (
    response.relayUrl,
    response.okReceived,
    response.broadcastSuccessful,
    response.msg,
  );

  test('collects the OK of every relay', () async {
    final first = await startRelay();
    final second = await startRelay();
    final event = signedEvent(content: 'hello');

    final responses = await publishes
        .publish(event, relays: [first.url, second.url])
        .done;

    expect(
      responses.values.map(summary),
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

    expect(responses.values.map(summary), [
      (relay.url, true, false, 'blocked: spam'),
    ]);
  });

  test('fails a relay it cannot connect to', () async {
    const blocked = 'wss://blocked.example';
    manager.blockedRelays.add(blocked);

    final responses = await publishes
        .publish(signedEvent(), relays: [blocked])
        .done;

    expect(responses.values.map(summary), [
      (blocked, false, false, 'could not connect'),
    ]);
  });

  test('refuses an unsigned event', () {
    final unsigned = Nip01Event(pubKey: alice, kind: 1, tags: [], content: '');

    expect(
      () => publishes.publish(unsigned, relays: ['wss://relay.example']),
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
        .publish(signedEvent(), relays: [relay.url, '${relay.url}/'])
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
    expect(manager.isBroadcasting(event.id), isTrue);
    final responses = await Future.wait(broadcasts);

    for (final response in responses) {
      expect(response.values.single.broadcastSuccessful, isTrue);
    }
    expect(manager.isBroadcasting(event.id), isFalse);
  });

  test('is done once enough relays accepted the event', () async {
    final fast = await startRelay();
    final silent = await startRelay(answerEvents: false);

    final responses = await publishes
        .publish(
          signedEvent(),
          relays: [fast.url, silent.url],
          considerDonePercent: 0.5,
        )
        .done
        .timeout(const Duration(seconds: 3));

    expect(
      responses.values
          .where((r) => r.broadcastSuccessful)
          .map((r) => r.relayUrl),
      [fast.url],
    );
  });

  test('does not count a refusal towards considerDonePercent', () async {
    final refusing = await startRelay(rejectEventsWith: 'blocked: no');
    final silent = await startRelay(answerEvents: false);
    final publish = publishes.publish(
      signedEvent(),
      relays: [refusing.url, silent.url],
      considerDonePercent: 0.5,
      timeout: const Duration(milliseconds: 500),
    );
    var done = false;
    unawaited(publish.done.then((_) => done = true));

    await eventually(() => publish.outcomes[refusing.url]!.okReceived);
    await pumpEventQueue();
    expect(done, isFalse, reason: 'the refusal made it look half done');

    final responses = await publish.done;
    expect(responses[refusing.url]!.broadcastSuccessful, isFalse);
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

  group('open', () {
    test('is in flight before it is signed', () async {
      final relay = await startRelay();
      final event = signedEvent();
      final unsigned = Nip01Event(
        pubKey: event.pubKey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
      );

      final publish = publishes.open(unsigned);
      expect(manager.isBroadcasting(event.id), isTrue);

      publish.start(event);
      expect(publish.send(relay.url), isTrue);
      publish.seal();
      final responses = await publish.done;

      expect(responses.values.single.broadcastSuccessful, isTrue);
      expect(relay.events.single.sig, event.sig);
      expect(manager.isBroadcasting(event.id), isFalse);
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
      expect(publish.send('${relay.url}/'), isFalse);
      expect(publish.send('https://relay.example'), isFalse);
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

      expect(outcomes[relay.url]!.broadcastSuccessful, isTrue);
      expect(publish.outcomes, outcomes);
      expect((await updates).last[relay.url]!.broadcastSuccessful, isTrue);
    });

    test('cannot be sent before it is started', () {
      final publish = publishes.open(signedEvent());

      expect(() => publish.send('wss://relay.example'), throwsStateError);
    });

    test('refuses to start unsigned', () {
      final unsigned = Nip01Event(
        pubKey: alice,
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
      expect(manager.isBroadcasting(asked.id), isTrue);
      final responses = await publish.done;

      expect(relay.events.single.id, signed.id);
      expect(responses.values.single.broadcastSuccessful, isTrue);
      expect(manager.isBroadcasting(asked.id), isFalse);
      expect(manager.isBroadcasting(signed.id), isFalse);
    });

    test('fails with the error it is given', () async {
      final event = signedEvent();
      final publish = publishes.open(event);

      publish.fail(StateError('signer refused'));

      await expectLater(publish.done, throwsA(isA<StateError>()));
      expect(manager.isBroadcasting(event.id), isFalse);
    });
  });
}
