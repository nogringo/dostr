import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

const _relays = UrlSet.explicit(['wss://a']);

/// A record of [event] as the store holds it, already attempted once.
QueuedPublish _stored(
  Nip01Event event, {
  required int createdAt,
  required int nextAttemptAt,
}) => QueuedPublish(
  id: event.id,
  event: event,
  relays: [RelayUrl.parse('wss://a')],
  ackedRelays: const [],
  lastErrors: const {},
  terminalErrors: const {},
  inaccessibleAttempts: const {},
  attempts: 1,
  firstAttemptAt: createdAt,
  lastAttemptAt: createdAt,
  nextAttemptAt: nextAttemptAt,
  deliveredAt: null,
  failedAt: null,
  createdAt: createdAt,
);

void main() {
  late MemoryPublishQueueStore store;
  late FakePublisher fake;

  setUp(() {
    store = MemoryPublishQueueStore();
    fake = FakePublisher();
  });

  PublishQueue newQueue({required int maxConcurrentPublishes}) => PublishQueue(
    publishFn: fake.fn,
    store: store,
    maxConcurrentPublishes: maxConcurrentPublishes,
  );

  test('at most maxConcurrentPublishes attempts publish at once', () async {
    fake.gate = Completer<Map<RelayUrl, RelayPublishOutcome>>();
    final queue = newQueue(maxConcurrentPublishes: 2);
    final events = [
      for (var seed = 1; seed <= 3; seed++) makeEvent(seed: seed),
    ];

    for (final event in events) {
      await queue.publish(event, relaySet: _relays);
    }
    await waitFor(queue, events.first.id, (_) => fake.calls.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fake.calls.map((c) => c.event.id), [events[0].id, events[1].id]);

    fake.gate!.complete({
      RelayUrl.parse('wss://a'): const RelayPublishOutcome.accepted(),
    });
    for (final event in events) {
      await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
    }
    expect(fake.calls.map((c) => c.event.id), [for (final e in events) e.id]);

    await queue.dispose();
  });

  test('due entries go out in the order they were queued', () async {
    fake.ack('wss://a');
    final events = [
      for (var seed = 1; seed <= 3; seed++) makeEvent(seed: seed),
    ];
    await store.put([
      for (final (index, event) in events.indexed)
        _stored(event, createdAt: index, nextAttemptAt: events.length - index),
    ]);

    final queue = newQueue(maxConcurrentPublishes: 1)..start();
    for (final event in events) {
      await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
    }
    expect(fake.calls.map((c) => c.event.id), [for (final e in events) e.id]);

    await queue.dispose();
  });

  test('dispose abandons the attempts waiting for a slot', () async {
    fake.gate = Completer<Map<RelayUrl, RelayPublishOutcome>>();
    final queue = newQueue(maxConcurrentPublishes: 1);
    final first = makeEvent(seed: 1);
    final second = makeEvent(seed: 2);

    await queue.publish(first, relaySet: _relays);
    await queue.publish(second, relaySet: _relays);
    await waitFor(queue, first.id, (_) => fake.calls.isNotEmpty);
    await queue.dispose().timeout(const Duration(seconds: 1));

    expect(fake.calls, hasLength(1));
  });

  test('rejects a maxConcurrentPublishes below one', () {
    expect(() => newQueue(maxConcurrentPublishes: 0), throwsArgumentError);
  });
}
