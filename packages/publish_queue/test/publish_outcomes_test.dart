import 'dart:async';
import 'dart:math';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

void main() {
  late Database db;
  late FakePublisher fake;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
    fake = FakePublisher();
  });

  tearDown(() async {
    await db.close();
  });

  PublishQueue newQueue({
    int maxInaccessibleAttemptsPerRelay = 12,
    Stream<bool>? onlineSignal,
    Duration initialBackoff = const Duration(milliseconds: 1),
    Duration maxBackoff = const Duration(minutes: 30),
    Random? random,
  }) => PublishQueue(
    publishFn: fake.fn,
    db: db,
    initialBackoff: initialBackoff,
    maxBackoff: maxBackoff,
    maxInaccessibleAttemptsPerRelay: maxInaccessibleAttemptsPerRelay,
    onlineSignal: onlineSignal,
    random: random,
  );

  test('publish rejects an unsigned event and stores nothing', () async {
    final queue = newQueue();
    final unsigned = Nip01Event(pubkey: 'a' * 64, kind: 1, content: 'hi');

    await expectLater(
      queue.publish(unsigned, relaySet: const UrlSet.explicit(['wss://a'])),
      throwsArgumentError,
    );
    expect(await queue.listAll(), isEmpty);
    expect(fake.calls, isEmpty);

    await queue.dispose();
  });

  test('urls that are not ws or wss urls are dropped', () async {
    fake.ack('wss://a');
    final queue = newQueue();

    final record = await queue.publish(
      makeEvent(),
      relaySet: const UrlSet.explicit([
        'https://relay.example',
        'relay.example',
        'wss://a',
      ]),
    );
    expect(record.relays, ['wss://a']);

    await queue.dispose();
  });

  test('republish rejects a relay that is not a relay url', () async {
    fake.ack('wss://a');
    final queue = newQueue();
    final event = makeEvent();
    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));

    await expectLater(
      queue.republish(event.id, relay: 'https://a'),
      throwsArgumentError,
    );

    await queue.dispose();
  });

  test('the publishFn gets the account the event was queued under', () async {
    fake.ack('wss://a');
    final queue = newQueue();

    await queue.publish(
      makeEvent(),
      relaySet: const UrlSet.explicit(['wss://a']),
      account: 'alice',
    );
    await queue.publish(
      makeEvent(seed: 2),
      relaySet: const UrlSet.explicit(['wss://a']),
    );
    while (fake.calls.length < 2) {
      await Future.delayed(const Duration(milliseconds: 5));
    }

    expect(fake.calls.map((c) => c.account), unorderedEquals(['alice', null]));

    await queue.dispose();
  });

  test('an event too long for a relay fails it for good', () async {
    fake.fail('wss://a', kind: RelayFailureKind.messageTooLong, detail: '512');
    final queue = newQueue();
    final event = makeEvent();

    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    final failed = await waitFor(
      queue,
      event.id,
      (r) => r.status == QueuedPublishStatus.failed,
    );
    expect(failed.terminalErrors, {'wss://a': 'messageTooLong: 512'});

    await queue.dispose();
  });

  test('a relay the RelayManager blocks fails it for good', () async {
    fake.fail('wss://a', kind: RelayFailureKind.blocked, detail: 'by the user');
    final queue = newQueue();
    final event = makeEvent();

    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    final failed = await waitFor(
      queue,
      event.id,
      (r) => r.status == QueuedPublishStatus.failed,
    );
    expect(failed.terminalErrors, {'wss://a': 'blocked: by the user'});
    expect(failed.inaccessibleAttempts, isEmpty);
    expect(fake.calls, hasLength(1));

    await queue.dispose();
  });

  test('a timed out relay counts as unreachable', () async {
    fake.timeOut('wss://a');
    final queue = newQueue(maxInaccessibleAttemptsPerRelay: 1);
    final event = makeEvent();

    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    final failed = await waitFor(
      queue,
      event.id,
      (r) => r.status == QueuedPublishStatus.failed,
    );
    expect(failed.terminalErrors, {
      'wss://a': 'max-inaccessible-attempts: timed out',
    });

    await queue.dispose();
  });

  test(
    'an identity a relay cannot use does not count as unreachable',
    () async {
      fake.fail('wss://a', kind: RelayFailureKind.cannotSign, detail: 'no key');
      final queue = newQueue(maxInaccessibleAttemptsPerRelay: 1);
      final event = makeEvent();

      await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
      final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(pending.status, QueuedPublishStatus.pending);
      expect(pending.inaccessibleAttempts, isEmpty);
      expect(pending.lastErrors, {'wss://a': 'cannotSign: no key'});

      await queue.dispose();
    },
  );

  test('a relay that answers resets its unreachable count', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final event = makeEvent();

    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    await waitFor(queue, event.id, (r) => r.inaccessibleAttempts.isNotEmpty);

    fake.refuse('wss://a', message: 'rate-limited: slow down');
    await queue.republish(event.id);
    final answered = await waitFor(
      queue,
      event.id,
      (r) => r.inaccessibleAttempts.isEmpty,
    );
    expect(answered.lastErrors, {'wss://a': 'rate-limited: slow down'});

    await queue.dispose();
  });

  group('offline attempts', () {
    test('a relay that answers shows the device is online', () async {
      fake.refuse('wss://a', message: 'rate-limited: slow down');
      final queue = newQueue(onlineSignal: Stream.value(false))..start();
      await Future<void>.delayed(Duration.zero);
      final event = makeEvent();

      await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://a', 'wss://gone']),
      );
      final record = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(record.inaccessibleAttempts, {'wss://gone': 1});

      await queue.dispose();
    });

    test('an attempt that ends offline does not count', () async {
      final online = StreamController<bool>();
      fake.gate = Completer<Map<RelayUrl, RelayPublishOutcome>>();
      final queue = newQueue(onlineSignal: online.stream)..start();
      final event = makeEvent();

      await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://gone']),
      );
      await waitFor(queue, event.id, (_) => fake.calls.isNotEmpty);
      online.add(false);
      await Future<void>.delayed(Duration.zero);
      fake.gate!.complete(const {});

      final record = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(record.inaccessibleAttempts, isEmpty);
      expect(record.lastErrors, {'wss://gone': 'no response'});

      await queue.dispose();
      await online.close();
    });

    test('an offline attempt does not grow the backoff', () async {
      Future<List<int>> delays({required bool online}) async {
        final queue = newQueue(
          onlineSignal: Stream.value(online),
          initialBackoff: const Duration(milliseconds: 50),
          random: _LongestJitter(),
        )..start();
        await Future<void>.delayed(Duration.zero);
        final event = makeEvent(seed: online ? 1 : 2);
        await queue.publish(
          event,
          relaySet: const UrlSet.explicit(['wss://gone']),
        );
        final delays = <int>[];
        for (var attempts = 1; attempts <= 3; attempts++) {
          final record = await waitFor(
            queue,
            event.id,
            (r) => r.attempts >= attempts,
          );
          delays.add(record.nextAttemptAt - record.lastAttemptAt!);
          await queue.republish(event.id);
        }
        await queue.dispose();
        return delays;
      }

      expect(await delays(online: false), everyElement(lessThan(90)));
      expect((await delays(online: true)).last, greaterThanOrEqualTo(200));
    });

    test('the backoff starts over once back online', () async {
      final online = StreamController<bool>();
      final queue = newQueue(
        onlineSignal: online.stream,
        initialBackoff: const Duration(milliseconds: 50),
        random: _LongestJitter(),
      )..start();
      online.add(false);
      await Future<void>.delayed(Duration.zero);
      final event = makeEvent();

      await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://gone']),
      );
      for (var attempts = 1; attempts <= 3; attempts++) {
        await waitFor(queue, event.id, (r) => r.attempts >= attempts);
        if (attempts < 3) await queue.republish(event.id);
      }
      expect((await queue.get(event.id))!.onlineFailures, 0);

      online.add(true);
      await Future<void>.delayed(Duration.zero);
      await queue.republish(event.id);
      final record = await waitFor(queue, event.id, (r) => r.attempts >= 4);
      expect(record.onlineFailures, record.attempts - 3);
      expect(record.nextAttemptAt - record.lastAttemptAt!, lessThan(200));

      await queue.dispose();
      await online.close();
    });
  });

  test('publish resets the backoff of an existing entry', () async {
    fake.refuse('wss://a', message: 'rate-limited: slow down');
    final queue = newQueue(
      initialBackoff: const Duration(milliseconds: 50),
      random: _LongestJitter(),
    );
    final event = makeEvent();

    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    for (var attempts = 1; attempts <= 3; attempts++) {
      await waitFor(queue, event.id, (r) => r.attempts >= attempts);
      if (attempts < 3) await queue.republish(event.id);
    }
    expect((await queue.get(event.id))!.onlineFailures, 3);

    final queued = await queue.publish(
      event,
      relaySet: const UrlSet.explicit(['wss://b']),
    );
    expect(queued.onlineFailures, 0);
    final record = await waitFor(queue, event.id, (r) => r.attempts >= 4);
    expect(record.onlineFailures, 1);
    expect(record.nextAttemptAt - record.lastAttemptAt!, lessThan(90));

    await queue.dispose();
  });

  test('dispose abandons an attempt waiting on the network', () async {
    fake.gate = Completer<Map<RelayUrl, RelayPublishOutcome>>();
    final queue = newQueue();
    final event = makeEvent();

    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    await waitFor(queue, event.id, (_) => fake.calls.isNotEmpty);
    await queue.dispose().timeout(const Duration(seconds: 1));

    final queueAgain = newQueue();
    final record = (await queueAgain.get(event.id))!;
    expect(record.attempts, 0);
    expect(record.status, QueuedPublishStatus.pending);
    await queueAgain.dispose();
  });
}

/// Always draws the longest backoff, so that a growing one shows.
class _LongestJitter implements Random {
  @override
  double nextDouble() => 1;

  @override
  bool nextBool() => true;

  @override
  int nextInt(int max) => max - 1;
}
