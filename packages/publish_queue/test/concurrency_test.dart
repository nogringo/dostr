import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

class _SlowStore extends MemoryPublishQueueStore {
  @override
  Future<void> put(List<QueuedPublish> records) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await super.put(records);
  }
}

void main() {
  late FakePublisher fake;

  setUp(() {
    fake = FakePublisher()..gate = Completer();
  });

  PublishQueue newQueue({PublishQueueStore? store}) => PublishQueue(
    publishFn: fake.fn,
    store: store ?? MemoryPublishQueueStore(),
    initialBackoff: const Duration(hours: 1),
    maxBackoff: const Duration(hours: 1),
  );

  void acceptParkedAttempt(String relay) {
    final gate = fake.gate!;
    fake.gate = null;
    gate.complete({
      RelayUrl.parse(relay): const RelayPublishOutcome.accepted(),
    });
  }

  test('a republish during an attempt pushes once it is done', () async {
    final queue = newQueue();
    final event = makeEvent();
    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    await waitFor(queue, event.id, (_) => fake.calls.isNotEmpty);

    await queue.republish(event.id, relay: 'wss://a');
    fake.ack('wss://a');
    acceptParkedAttempt('wss://a');

    final pushed = await waitFor(
      queue,
      event.id,
      (r) => r.attempts == 2 && r.forcedRelays == null,
    );
    expect(pushed.status, QueuedPublishStatus.delivered);
    expect(fake.calls, hasLength(2));

    await queue.dispose();
  });

  test('a publish during an attempt keeps the acks it records', () async {
    final queue = newQueue(store: _SlowStore());
    final event = makeEvent();
    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    await waitFor(queue, event.id, (_) => fake.calls.isNotEmpty);

    acceptParkedAttempt('wss://a');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://b']));
    fake.ack('wss://b');

    final delivered = await waitFor(
      queue,
      event.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );
    expect(delivered.ackedRelays, unorderedEquals(['wss://a', 'wss://b']));
    expect(delivered.attempts, 2);
    expect(fake.calls.last.relays, ['wss://b']);

    await queue.dispose();
  });

  test('a publish called before a clear is cleared with it', () async {
    final queue = newQueue();
    final event = makeEvent();

    final publishing = queue.publish(
      event,
      relaySet: const UrlSet.explicit(['wss://a']),
      account: 'alice',
    );
    await queue.clearLocalAccountData(account: 'alice');
    await publishing;
    expect(await queue.get(event.id, account: 'alice'), isNull);

    await queue.dispose();
  });
}
