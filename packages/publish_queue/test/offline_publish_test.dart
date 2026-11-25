import 'dart:async';

import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'publish persists immediately and marks delivered once all ack',
    () async {
      final fake = FakePublisher();
      fake.ackAll(['wss://a', 'wss://b']);
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 10),
      );

      final event = makeEvent();
      final record = await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
      );
      expect(record.status, QueuedPublishStatus.pending);

      final delivered = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
      expect(delivered.ackedRelays, unorderedEquals(['wss://a', 'wss://b']));
      expect(delivered.lastErrors, isEmpty);
      expect(fake.calls.length, 1);

      await queue.dispose();
    },
  );

  test('partial success leaves remaining relays pending', () async {
    final fake = FakePublisher();
    fake.ackAll(['wss://a']);
    fake.fail('wss://b', detail: 'pow too low');
    final queue = PublishQueue(
      publishFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 5),
    );

    final event = makeEvent();
    await queue.publish(
      event,
      relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
    );

    final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
    expect(pending.status, QueuedPublishStatus.pending);
    expect(pending.ackedRelays, ['wss://a']);
    expect(pending.remainingRelays, ['wss://b']);
    expect(pending.lastErrors['wss://b'], 'unreachable: pow too low');

    await queue.dispose();
  });

  test(
    'terminal OK false prefixes stop retrying and mark the entry failed',
    () async {
      const terminalMessages = {
        'wss://blocked': 'blocked: you are banned',
        'wss://invalid': 'invalid: bad event',
        'wss://mute': 'mute: no one was listening to your ephemeral event',
        'wss://pow': 'pow: difficulty 26 is less than 30',
        'wss://restricted': 'restricted: kind not allowed',
      };

      for (final entry in terminalMessages.entries) {
        final fake = FakePublisher();
        fake.refuse(entry.key, message: entry.value);
        final queue = PublishQueue(
          publishFn: fake.fn,
          db: db,
          initialBackoff: const Duration(milliseconds: 1),
        );

        final event = makeEvent(seed: entry.key.hashCode);
        await queue.publish(event, relaySet: UrlSet.explicit([entry.key]));

        final failed = await waitFor(
          queue,
          event.id,
          (r) => r.status == QueuedPublishStatus.failed,
        );
        expect(failed.ackedRelays, isEmpty);
        expect(failed.remainingRelays, isEmpty);
        expect(failed.lastErrors, isEmpty);
        expect(failed.terminalErrors, {entry.key: entry.value});
        expect(failed.failedAt, isNotNull);

        await queue.retryNow();
        expect(fake.calls.length, 1);

        await queue.dispose();
        await db.close();
        db = await newDatabaseFactoryMemory().openDatabase('test.db');
      }
    },
  );

  test(
    'terminal prefix parsing is case-insensitive and requires colon',
    () async {
      final fake = FakePublisher();
      fake.refuse('wss://a', message: 'PoW: too low');
      fake.refuse('wss://b', message: 'pow too low');
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
      );

      final event = makeEvent();
      await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
      );

      final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(pending.status, QueuedPublishStatus.pending);
      expect(pending.terminalErrors, {'wss://a': 'PoW: too low'});
      expect(pending.lastErrors, {'wss://b': 'pow too low'});
      expect(pending.remainingRelays, ['wss://b']);

      fake.ackAll(['wss://b']);
      await queue.retryNow();
      final failed = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.failed,
      );
      expect(failed.ackedRelays, ['wss://b']);
      expect(failed.terminalErrors.keys, ['wss://a']);
      expect(fake.calls.last.relays, ['wss://b']);

      await queue.dispose();
    },
  );

  test(
    'retryable OK false prefixes and transport failures keep retrying',
    () async {
      final fake = FakePublisher();
      fake.refuse('wss://rate', message: 'rate-limited: slow down');
      fake.refuse(
        'wss://error',
        message: 'error: could not connect to the database',
      );
      fake.refuse('wss://unknown', message: 'mystery: nope');
      fake.refuse('wss://empty', message: '');
      fake.fail('wss://transport', detail: 'pow: from transport path');
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
      );

      final event = makeEvent();
      await queue.publish(
        event,
        relaySet: const UrlSet.explicit([
          'wss://rate',
          'wss://error',
          'wss://unknown',
          'wss://empty',
          'wss://no-response',
          'wss://transport',
        ]),
      );

      final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(pending.status, QueuedPublishStatus.pending);
      expect(pending.terminalErrors, isEmpty);
      expect(
        pending.remainingRelays,
        unorderedEquals([
          'wss://rate',
          'wss://error',
          'wss://unknown',
          'wss://empty',
          'wss://no-response',
          'wss://transport',
        ]),
      );
      expect(pending.lastErrors['wss://rate'], 'rate-limited: slow down');
      expect(
        pending.lastErrors['wss://error'],
        'error: could not connect to the database',
      );
      expect(pending.lastErrors['wss://unknown'], 'mystery: nope');
      expect(pending.lastErrors['wss://empty'], 'refused');
      expect(pending.lastErrors['wss://no-response'], 'no response');
      expect(
        pending.lastErrors['wss://transport'],
        'unreachable: pow: from transport path',
      );

      fake.ackAll([
        'wss://rate',
        'wss://error',
        'wss://unknown',
        'wss://empty',
        'wss://no-response',
        'wss://transport',
      ]);
      await queue.retryNow();
      await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
      expect(
        fake.calls.last.relays,
        unorderedEquals([
          'wss://rate',
          'wss://error',
          'wss://unknown',
          'wss://empty',
          'wss://no-response',
          'wss://transport',
        ]),
      );

      await queue.dispose();
    },
  );

  test(
    'inaccessible relay becomes terminal after online attempt threshold',
    () async {
      final fake = FakePublisher();
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
        maxInaccessibleAttemptsPerRelay: 2,
      );

      final event = makeEvent();
      await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://gone']),
      );

      final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(pending.status, QueuedPublishStatus.pending);
      expect(pending.inaccessibleAttempts, {'wss://gone': 1});
      expect(pending.remainingRelays, ['wss://gone']);

      await Future.delayed(const Duration(milliseconds: 5));
      await queue.retryNow();
      final failed = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.failed,
      );
      expect(failed.remainingRelays, isEmpty);
      expect(failed.inaccessibleAttempts, {'wss://gone': 2});
      expect(
        failed.terminalErrors['wss://gone'],
        'max-inaccessible-attempts: no response',
      );

      await queue.retryNow();
      expect(fake.calls.length, 2);

      await queue.dispose();
    },
  );

  test(
    'offline inaccessible attempts do not count toward terminal failure',
    () async {
      final online = StreamController<bool>();
      final fake = FakePublisher();
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
        maxInaccessibleAttemptsPerRelay: 1,
        onlineSignal: online.stream,
      );
      queue.start();
      online.add(false);
      await Future.delayed(const Duration(milliseconds: 5));

      final event = makeEvent();
      await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://gone']),
      );

      final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(pending.status, QueuedPublishStatus.pending);
      expect(pending.inaccessibleAttempts, isEmpty);
      expect(pending.terminalErrors, isEmpty);

      await online.close();
      await queue.dispose();
    },
  );

  test(
    'global publisher exceptions do not count as relay inaccessible',
    () async {
      final fake = FakePublisher()..error = StateError('no signer');
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
        maxInaccessibleAttemptsPerRelay: 1,
      );

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
      final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(pending.status, QueuedPublishStatus.pending);
      expect(pending.inaccessibleAttempts, isEmpty);
      expect(pending.terminalErrors, isEmpty);
      expect(pending.lastErrors['wss://a'], contains('no signer'));

      await queue.dispose();
    },
  );

  test('ok false relay responses do not count as inaccessible', () async {
    final fake = FakePublisher();
    fake.refuse('wss://rate', message: 'rate-limited: slow down');
    final queue = PublishQueue(
      publishFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 1),
      maxInaccessibleAttemptsPerRelay: 1,
    );

    final event = makeEvent();
    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://rate']));
    final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
    expect(pending.status, QueuedPublishStatus.pending);
    expect(pending.inaccessibleAttempts, isEmpty);
    expect(pending.terminalErrors, isEmpty);
    expect(pending.lastErrors['wss://rate'], 'rate-limited: slow down');

    await queue.dispose();
  });

  test(
    'mixed terminal and retryable failures only retry retryable relays',
    () async {
      final fake = FakePublisher();
      fake.ackAll(['wss://a']);
      fake.refuse('wss://b', message: 'restricted: kind not allowed');
      fake.fail('wss://c', detail: 'temporary outage');
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
      );

      final event = makeEvent();
      await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://a', 'wss://b', 'wss://c']),
      );

      final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(pending.status, QueuedPublishStatus.pending);
      expect(pending.ackedRelays, ['wss://a']);
      expect(pending.terminalErrors, {
        'wss://b': 'restricted: kind not allowed',
      });
      expect(pending.remainingRelays, ['wss://c']);

      fake.ackAll(['wss://c']);
      await queue.retryNow();
      final failed = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.failed,
      );
      expect(failed.ackedRelays, unorderedEquals(['wss://a', 'wss://c']));
      expect(failed.terminalErrors.keys, ['wss://b']);
      expect(fake.calls.last.relays, ['wss://c']);

      await queue.dispose();
    },
  );

  test('watchPending excludes terminally failed entries', () async {
    final fake = FakePublisher();
    fake.refuse('wss://a', message: 'invalid: malformed');
    final queue = PublishQueue(
      publishFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 1),
    );

    final event = makeEvent();
    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    await waitFor(
      queue,
      event.id,
      (r) => r.status == QueuedPublishStatus.failed,
    );

    final pending = await queue.watchPending().first;
    expect(pending, isEmpty);

    await queue.dispose();
  });

  test(
    'forced republish can recover a terminal failure when relay later succeeds',
    () async {
      final fake = FakePublisher();
      fake.refuse('wss://a', message: 'pow: too low');
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
      );

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
      final failed = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.failed,
      );
      final failedAt = failed.failedAt;

      fake.ackAll(['wss://a']);
      await queue.republish(event.id, relay: 'wss://a');
      final delivered = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
      expect(delivered.ackedRelays, ['wss://a']);
      expect(delivered.terminalErrors, isEmpty);
      expect(delivered.failedAt, isNull);
      expect(delivered.deliveredAt, isNot(failedAt));
      expect(fake.calls.last.relays, ['wss://a']);

      await queue.dispose();
    },
  );

  test('retryNow only targets remaining relays', () async {
    final fake = FakePublisher();
    fake.ackAll(['wss://a']);
    fake.fail('wss://b');
    final queue = PublishQueue(
      publishFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 1),
    );

    final event = makeEvent();
    await queue.publish(
      event,
      relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
    );
    await waitFor(queue, event.id, (r) => r.attempts >= 1);

    // Now have wss://b ack.
    fake.ackAll(['wss://b']);
    await queue.retryNow();
    final delivered = await waitFor(
      queue,
      event.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );

    expect(delivered.ackedRelays, unorderedEquals(['wss://a', 'wss://b']));
    // The retry call should have used only wss://b (the remaining relay).
    expect(fake.calls.last.relays, ['wss://b']);

    await queue.dispose();
  });

  test(
    'republish() forces a push to every relay without losing acks or delivered status',
    () async {
      final fake = FakePublisher();
      fake.ackAll(['wss://a', 'wss://b']);
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
      );

      final event = makeEvent();
      await queue.publish(
        event,
        relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
      );
      final delivered = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
      final originalDeliveredAt = delivered.deliveredAt!;
      final attemptsBefore = delivered.attempts;

      // Simulate one relay being momentarily unreachable during the republish.
      // The historical ack must not be invalidated by this transient failure.
      fake.responders.clear();
      fake.ackAll(['wss://a']);
      fake.fail('wss://b', detail: 'temporary glitch');

      await queue.republish(event.id);

      final after = await waitFor(
        queue,
        event.id,
        (r) => r.attempts > attemptsBefore,
      );
      expect(
        after.ackedRelays,
        unorderedEquals(['wss://a', 'wss://b']),
        reason: 'past acks must be monotonic',
      );
      expect(after.status, QueuedPublishStatus.delivered);
      expect(
        after.deliveredAt,
        originalDeliveredAt,
        reason: 'deliveredAt is a historical fact and must not move',
      );
      expect(
        after.lastErrors,
        isEmpty,
        reason: 'transient failures on already-acked relays are not surfaced',
      );
      // The force-push targeted ALL relays this time, not just remaining.
      expect(fake.calls.last.relays, unorderedEquals(['wss://a', 'wss://b']));

      await queue.dispose();
    },
  );

  test(
    'republish(id, relay:) adds a new relay and only pushes to it',
    () async {
      final fake = FakePublisher();
      fake.ackAll(['wss://a']);
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
      );

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
      await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );

      fake.fail('wss://c');
      await queue.republish(event.id, relay: 'wss://c');

      final withC = await waitFor(
        queue,
        event.id,
        (r) => r.relays.contains('wss://c') && r.attempts >= 2,
      );
      expect(withC.relays, containsAll(['wss://a', 'wss://c']));
      expect(
        withC.status,
        QueuedPublishStatus.pending,
        reason: 'a new unacked relay demotes the entry from delivered',
      );
      expect(withC.ackedRelays, [
        'wss://a',
      ], reason: 'the original ack stays monotonic');
      expect(withC.remainingRelays, ['wss://c']);
      // Force-push targeted only the named relay, not the whole list.
      expect(fake.calls.last.relays, ['wss://c']);

      await queue.dispose();
    },
  );

  test(
    'republish(id, relay:) on an already-acked relay re-pushes without losing the ack',
    () async {
      final fake = FakePublisher();
      fake.ackAll(['wss://a']);
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
      );

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
      final delivered = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
      final attemptsBefore = delivered.attempts;
      final originalDeliveredAt = delivered.deliveredAt!;

      // Same relay, but failing now. The history must survive.
      fake.responders.clear();
      fake.fail('wss://a');
      await queue.republish(event.id, relay: 'wss://a');

      final after = await waitFor(
        queue,
        event.id,
        (r) => r.attempts > attemptsBefore,
      );
      expect(after.ackedRelays, ['wss://a']);
      expect(after.status, QueuedPublishStatus.delivered);
      expect(after.deliveredAt, originalDeliveredAt);
      expect(after.lastErrors, isEmpty);
      expect(fake.calls.last.relays, ['wss://a']);

      await queue.dispose();
    },
  );

  test('publish() throws on empty relays', () async {
    final queue = PublishQueue(publishFn: FakePublisher().fn, db: db);
    expect(
      () => queue.publish(makeEvent(), relaySet: const UrlSet.explicit([])),
      throwsArgumentError,
    );
    await queue.dispose();
  });

  test('duplicate publish() merges relays and rearms', () async {
    final fake = FakePublisher();
    fake.ackAll(['wss://a']);
    fake.fail('wss://b');
    final queue = PublishQueue(
      publishFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 1),
    );

    final event = makeEvent();
    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
    await waitFor(queue, event.id, (r) => r.attempts >= 1);

    await queue.publish(event, relaySet: const UrlSet.explicit(['wss://b']));
    final merged = await waitFor(queue, event.id, (r) => r.relays.length == 2);
    expect(merged.relays, containsAll(['wss://a', 'wss://b']));

    await queue.dispose();
  });

  test('relay URLs are normalized (case, trailing slash) on storage', () async {
    final fake = FakePublisher();
    fake.ackAll(['wss://relay.example']);
    final queue = PublishQueue(
      publishFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 1),
    );

    final event = makeEvent();
    await queue.publish(
      event,
      relaySet: const UrlSet.explicit([
        'WSS://Relay.Example/',
        'wss://relay.example',
      ]),
    );
    final r = await waitFor(queue, event.id, (r) => r.attempts >= 1);
    expect(r.relays, ['wss://relay.example']);

    await queue.dispose();
  });

  test(
    'sync exception from publisher is recorded on remaining relays',
    () async {
      final fake = FakePublisher()..error = StateError('no signer');
      final queue = PublishQueue(
        publishFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 1),
      );

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
      final r = await waitFor(queue, event.id, (r) => r.attempts >= 1);
      expect(r.status, QueuedPublishStatus.pending);
      expect(r.lastErrors['wss://a'], contains('no signer'));

      await queue.dispose();
    },
  );

  test('dispose() blocks further public calls', () async {
    final queue = PublishQueue(publishFn: FakePublisher().fn, db: db);
    await queue.dispose();
    expect(
      () => queue.publish(
        makeEvent(),
        relaySet: const UrlSet.explicit(['wss://a']),
      ),
      throwsStateError,
    );
  });
}
