import 'dart:async';

import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

void main() {
  late FakePublisher fake;
  late int clock;

  setUp(() {
    fake = FakePublisher();
    clock = 1000;
  });

  PublishQueue newQueue({bool realClock = false}) => PublishQueue(
    publishFn: fake.fn,
    store: MemoryPublishQueueStore(),
    tickInterval: const Duration(milliseconds: 5),
    initialBackoff: const Duration(milliseconds: 5),
    maxBackoff: const Duration(milliseconds: 5),
    now: realClock ? null : () => clock,
  );

  DateTime at(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

  test('remove drops one record for good and returns it', () async {
    fake.fail('wss://a');
    final queue = newQueue(realClock: true)..start();
    final kept = makeEvent(seed: 1);
    final removed = makeEvent(seed: 2);
    await queue.publish(kept, relaySet: const UrlSet.explicit(['wss://a']));
    await queue.publish(removed, relaySet: const UrlSet.explicit(['wss://a']));

    expect((await queue.remove(removed.id))!.id, removed.id);
    expect(await queue.remove(removed.id), isNull);
    final pushes = fake.calls.where((c) => c.event.id == removed.id).length;
    await queue.retryNow();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      fake.calls.where((c) => c.event.id == removed.id),
      hasLength(pushes),
    );
    expect((await queue.listAll()).map((r) => r.id), [kept.id]);

    await queue.dispose();
  });

  test(
    'removeSettled drops the settled records queued before a date',
    () async {
      fake.ack('wss://a');
      fake.fail('wss://b');
      final queue = newQueue();
      final old = makeEvent(seed: 1);
      final pending = makeEvent(seed: 2);
      final recent = makeEvent(seed: 3);

      await queue.publish(old, relaySet: const UrlSet.explicit(['wss://a']));
      await queue.publish(
        pending,
        relaySet: const UrlSet.explicit(['wss://b']),
      );
      clock = 2000;
      await queue.publish(recent, relaySet: const UrlSet.explicit(['wss://a']));
      for (final event in [old, recent]) {
        await waitFor(
          queue,
          event.id,
          (r) => r.status == QueuedPublishStatus.delivered,
        );
      }

      await queue.removeSettled(queuedBefore: at(2000));
      expect(
        (await queue.listAll()).map((r) => r.id),
        unorderedEquals([pending.id, recent.id]),
      );

      await queue.dispose();
    },
  );

  test('removeSettled keeps a record with a republish queued', () async {
    fake.ack('wss://a');
    final queue = newQueue();
    final event = makeEvent();
    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    await waitFor(
      queue,
      event.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );

    fake.gate = Completer();
    await queue.republish(event.id);
    await queue.removeSettled(queuedBefore: at(2000));
    expect(await queue.get(event.id), isNotNull);

    fake.gate!.complete(const {});
    await queue.dispose();
  });
}
