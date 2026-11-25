import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

/// Fake publisher that fails every call (so entries stay pending and get
/// rescheduled by the worker). Useful to count how many times the worker
/// actually tries.
class FailingCounter {
  int calls = 0;
  PublishFn get fn => (event, relays, {account}) async {
    calls++;
    return {
      for (final relay in relays)
        relay: const RelayPublishOutcome.failed(
          RelayFailure(RelayFailureKind.unreachable, 'offline test'),
        ),
    };
  };
}

Nip01Event _event() => makeEvent();

/// Returns once one microtask + one event-loop tick has elapsed, which is
/// enough for a stream listener attached this turn to receive a pending
/// emission.
Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late MemoryPublishQueueStore store;

  setUp(() {
    store = MemoryPublishQueueStore();
  });

  test('periodic tick is a no-op while offline', () async {
    final fake = FailingCounter();
    final signal = StreamController<bool>();
    final queue = PublishQueue(
      publishFn: fake.fn,
      store: store,
      tickInterval: const Duration(milliseconds: 20),
      initialBackoff: const Duration(milliseconds: 5),
      onlineSignal: signal.stream,
    );

    // Seed the queue with a failing entry (so it stays pending and would
    // normally be picked up by every tick).
    await queue.publish(_event(), relaySet: const UrlSet.explicit(['wss://a']));
    queue.start();
    signal.add(false);
    // Let publish()'s unconditional attempt + start()'s initial replay
    // land, plus the signal listener flip _isOnline to false.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final base = fake.calls;

    // Run through several tick intervals while offline.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(
      fake.calls,
      base,
      reason: 'no periodic attempt should fire while offline',
    );

    await queue.dispose();
    await signal.close();
  });

  test('offline -> online edge triggers an immediate replay', () async {
    final fake = FailingCounter();
    final signal = StreamController<bool>();
    final queue = PublishQueue(
      publishFn: fake.fn,
      store: store,
      // Long interval so we know any replay came from the edge, not the timer.
      tickInterval: const Duration(seconds: 30),
      initialBackoff: const Duration(milliseconds: 5),
      onlineSignal: signal.stream,
    );

    await queue.publish(_event(), relaySet: const UrlSet.explicit(['wss://a']));
    await _flush();
    final base = fake.calls;
    expect(base, 1);

    queue.start();
    signal.add(false);
    await _flush();

    // Wait long enough for backoff to expire. If anything were going to fire
    // from the timer it would have, but the timer is 30s away.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fake.calls, base, reason: 'still offline, no new attempt');

    signal.add(true);
    await _flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      fake.calls,
      greaterThan(base),
      reason: 'flipping online must trigger an immediate replay',
    );

    await queue.dispose();
    await signal.close();
  });

  test('retryNow() bypasses the online state', () async {
    final fake = FailingCounter();
    final signal = StreamController<bool>();
    final queue = PublishQueue(
      publishFn: fake.fn,
      store: store,
      tickInterval: const Duration(seconds: 30),
      initialBackoff: const Duration(milliseconds: 5),
      onlineSignal: signal.stream,
    );

    await queue.publish(_event(), relaySet: const UrlSet.explicit(['wss://a']));
    queue.start();
    signal.add(false);
    // Let the initial attempt + start replay land and the entry's backoff
    // (5ms) elapse so it becomes due again.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final base = fake.calls;

    await queue.retryNow();
    await _flush();
    expect(
      fake.calls,
      greaterThan(base),
      reason: 'retryNow() must run even while offline',
    );

    await queue.dispose();
    await signal.close();
  });
}
