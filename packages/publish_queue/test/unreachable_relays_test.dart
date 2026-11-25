import 'dart:async';

import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

const _gone = UrlSet.explicit(['wss://gone']);

void main() {
  late FakePublisher fake;
  late int clock;

  setUp(() {
    fake = FakePublisher();
    clock = 0;
  });

  Future<PublishQueue> newQueue({
    int maxInaccessibleAttemptsPerRelay = 12,
    Stream<bool>? onlineSignal,
  }) async {
    final queue = PublishQueue(
      publishFn: fake.fn,
      store: MemoryPublishQueueStore(),
      tickInterval: const Duration(hours: 1),
      initialBackoff: const Duration(seconds: 10),
      maxBackoff: const Duration(seconds: 10),
      maxInaccessibleAttemptsPerRelay: maxInaccessibleAttemptsPerRelay,
      maxConcurrentPublishes: 1,
      onlineSignal: onlineSignal ?? Stream.value(true),
      now: () => clock,
    )..start();
    await Future<void>.delayed(Duration.zero);
    return queue;
  }

  test('an unreachable relay is tried once for every event owed it', () async {
    final queue = await newQueue();
    final events = [
      for (var seed = 1; seed <= 5; seed++) makeEvent(seed: seed),
    ];

    for (final event in events) {
      await queue.publish(event, relaySet: _gone);
    }
    for (final event in events) {
      final record = await waitFor(
        queue,
        event.id,
        (r) => r.inaccessibleAttempts.isNotEmpty,
      );
      expect(record.inaccessibleAttempts, {'wss://gone': 1});
      expect(record.lastErrors, {'wss://gone': 'no response'});
    }
    expect(fake.calls, hasLength(1));

    await queue.dispose();
  });

  test('an event owed a dead relay is cut off without trying it', () async {
    final queue = await newQueue(maxInaccessibleAttemptsPerRelay: 2);
    final first = makeEvent(seed: 1);
    final second = makeEvent(seed: 2);

    await queue.publish(first, relaySet: _gone);
    await waitFor(queue, first.id, (r) => r.inaccessibleAttempts.isNotEmpty);
    clock += const Duration(seconds: 10).inMilliseconds;
    await queue.retryNow();
    await waitFor(
      queue,
      first.id,
      (r) => r.status == QueuedPublishStatus.failed,
    );

    await queue.publish(second, relaySet: _gone);
    final failed = await waitFor(
      queue,
      second.id,
      (r) => r.status == QueuedPublishStatus.failed,
    );
    expect(failed.terminalErrors, {
      'wss://gone': 'max-inaccessible-attempts: no response',
    });
    expect(failed.attempts, 0);
    expect(fake.calls, hasLength(2));

    await queue.dispose();
  });

  test('the waits end when the device comes back online', () async {
    final online = StreamController<bool>();
    final queue = await newQueue(onlineSignal: online.stream);
    online.add(true);
    await Future<void>.delayed(Duration.zero);

    final first = makeEvent(seed: 1);
    await queue.publish(first, relaySet: _gone);
    await waitFor(queue, first.id, (_) => fake.calls.isNotEmpty);
    online
      ..add(false)
      ..add(true);
    await Future<void>.delayed(Duration.zero);

    final second = makeEvent(seed: 2);
    await queue.publish(second, relaySet: _gone);
    await waitFor(queue, second.id, (r) => r.attempts >= 1);
    expect(fake.calls, hasLength(2));

    await queue.dispose();
    await online.close();
  });
}
