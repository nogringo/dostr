import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

const _alice = 'alice';
const _bob = 'bob';
const _relays = UrlSet.explicit(['wss://a']);

Nip01Event _version({
  int kind = 10002,
  required int createdAt,
  String? d,
  String pubkey = 'a',
  String content = '',
}) => Nip01Event(
  pubkey: pubkey * 64,
  kind: kind,
  createdAt: createdAt,
  tags: [
    if (d != null) ['d', d],
    ['r', 'wss://r$createdAt'],
  ],
  content: content,
  sig: fakeSig,
);

void main() {
  late MemoryPublishQueueStore store;
  late FakePublisher fake;

  setUp(() {
    store = MemoryPublishQueueStore();
    fake = FakePublisher();
  });

  PublishQueue newQueue({UrlListFn? relayListFn}) => PublishQueue(
    publishFn: fake.fn,
    relayListFn: relayListFn,
    store: store,
    tickInterval: const Duration(milliseconds: 5),
    initialBackoff: const Duration(milliseconds: 5),
    maxBackoff: const Duration(milliseconds: 5),
  )..start();

  int pushesOf(Nip01Event event) =>
      fake.calls.where((c) => c.event.id == event.id).length;

  test(
    'an older version waits while a newer one heads to its relays',
    () async {
      fake.fail('wss://a');
      final queue = newQueue();
      final v1 = _version(createdAt: 100);
      final v2 = _version(createdAt: 200);

      await queue.publish(v1, relaySet: _relays);
      await waitFor(queue, v1.id, (r) => r.attempts >= 1);
      await queue.publish(v2, relaySet: _relays);
      await waitFor(queue, v2.id, (r) => r.attempts >= 1);
      final pushes = pushesOf(v1);
      await waitFor(queue, v2.id, (r) => r.attempts >= 4);
      expect(pushesOf(v1), pushes);
      expect((await queue.get(v1.id))!.status, QueuedPublishStatus.pending);
      expect(
        (await queue.watchPending().first).map((r) => r.id),
        unorderedEquals([v1.id, v2.id]),
      );

      fake.ack('wss://a');
      final old = await waitFor(
        queue,
        v1.id,
        (r) => r.status == QueuedPublishStatus.superseded,
      );
      expect(old.supersededBy, v2.id);
      expect(pushesOf(v1), pushes);
      expect((await queue.watchPending().first), isEmpty);
      expect(await queue.listAll(), hasLength(2));

      await queue.dispose();
    },
  );

  test('an older version queued after a newer one is never sent', () async {
    fake.ack('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v2, relaySet: _relays);
    await waitFor(
      queue,
      v2.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );
    final queued = await queue.publish(v1, relaySet: _relays);
    expect(queued.status, QueuedPublishStatus.superseded);
    expect(queued.supersededBy, v2.id);

    await queue.retryNow();
    await Future.delayed(const Duration(milliseconds: 20));
    expect(pushesOf(v1), 0);
    expect((await queue.get(v2.id))!.status, QueuedPublishStatus.delivered);

    await queue.dispose();
  });

  test('a delivered older version stays delivered', () async {
    fake.ack('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v1, relaySet: _relays);
    await waitFor(
      queue,
      v1.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );
    await queue.publish(v2, relaySet: _relays);

    final old = (await queue.get(v1.id))!;
    expect(old.status, QueuedPublishStatus.delivered);
    expect(old.supersededBy, isNull);

    await queue.dispose();
  });

  test('an older version goes out once a newer one is cancelled', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v2, relaySet: _relays);
    await queue.publish(v1, relaySet: _relays);
    await waitFor(queue, v2.id, (r) => r.attempts >= 3);
    expect(pushesOf(v1), 0);

    await queue.cancel(v2.id);
    fake.ack('wss://a');
    await waitFor(
      queue,
      v1.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );

    await queue.dispose();
  });

  test('an older version goes out once a newer one is removed', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v2, relaySet: _relays);
    await queue.publish(v1, relaySet: _relays);
    await waitFor(queue, v2.id, (r) => r.attempts >= 3);
    expect(pushesOf(v1), 0);

    await queue.remove(v2.id);
    await waitFor(queue, v1.id, (r) => r.attempts >= 1);

    await queue.dispose();
  });

  test(
    'an older relay set waits for the same set of a newer version',
    () async {
      final queue = newQueue(
        relayListFn: (_, _) async => const UrlListLookup.unavailable('offline'),
      );
      final v1 = _version(createdAt: 100);
      final v2 = _version(createdAt: 200);

      await queue.publish(v2, relaySet: UrlSet.outbox(v2.pubkey));
      await queue.publish(v1, relaySet: UrlSet.outbox(v1.pubkey));
      await waitFor(queue, v2.id, (r) => r.resolutionAttempts >= 3);
      final old = (await queue.get(v1.id))!;
      expect(old.status, QueuedPublishStatus.pending);
      expect(old.resolutionAttempts, 0);
      expect(old.pendingRelaySet, UrlSet.outbox(v1.pubkey));

      await queue.dispose();
    },
  );

  test('publish reopens a superseded record', () async {
    fake.ackAll(['wss://a', 'wss://b']);
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v2, relaySet: _relays);
    await waitFor(
      queue,
      v2.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );
    final superseded = await queue.publish(v1, relaySet: _relays);
    expect(superseded.status, QueuedPublishStatus.superseded);

    final reopened = await queue.publish(
      v1,
      relaySet: const UrlSet.explicit(['wss://b']),
    );
    expect(reopened.status, QueuedPublishStatus.pending);
    expect(reopened.supersededBy, isNull);
    await waitFor(
      queue,
      v1.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );

    await queue.dispose();
  });

  test('addressable versions supersede each other per d tag', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final x1 = _version(kind: 30000, createdAt: 100, d: 'x');
    final y1 = _version(kind: 30000, createdAt: 150, d: 'y');
    final x2 = _version(kind: 30000, createdAt: 200, d: 'x');

    await queue.publish(x2, relaySet: _relays);
    await queue.publish(x1, relaySet: _relays);
    await queue.publish(y1, relaySet: _relays);
    await waitFor(queue, y1.id, (r) => r.attempts >= 2);
    expect(pushesOf(x1), 0);

    fake.ack('wss://a');
    final old = await waitFor(
      queue,
      x1.id,
      (r) => r.status == QueuedPublishStatus.superseded,
    );
    expect(old.supersededBy, x2.id);
    await waitFor(
      queue,
      y1.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );

    await queue.dispose();
  });

  test('versions with the same created_at keep the lowest id', () async {
    fake.ack('wss://a');
    final queue = newQueue();
    final versions = [
      _version(createdAt: 100, content: 'one'),
      _version(createdAt: 100, content: 'two'),
    ]..sort((a, b) => a.id.compareTo(b.id));
    final [lowest, highest] = versions;

    await queue.publish(lowest, relaySet: _relays);
    await waitFor(
      queue,
      lowest.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );
    final queued = await queue.publish(highest, relaySet: _relays);

    expect(queued.supersededBy, lowest.id);

    await queue.dispose();
  });

  test('regular events and other authors are never superseded', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final notes = [
      _version(kind: 1, createdAt: 100),
      _version(kind: 1, createdAt: 200),
    ];
    final lists = [
      _version(createdAt: 100, pubkey: 'a'),
      _version(createdAt: 200, pubkey: 'b'),
    ];

    for (final event in [...notes, ...lists]) {
      await queue.publish(event, relaySet: _relays);
    }

    for (final event in [...notes, ...lists]) {
      final record = await waitFor(queue, event.id, (r) => r.attempts >= 2);
      expect(record.status, QueuedPublishStatus.pending);
    }

    await queue.dispose();
  });

  test('versions supersede across accounts, the same event does not', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v1, relaySet: _relays, account: _alice);
    await queue.publish(v1, relaySet: _relays, account: _bob);
    for (final account in [_alice, _bob]) {
      final r = await waitFor(
        queue,
        v1.id,
        (r) => r.attempts >= 2,
        account: account,
      );
      expect(r.status, QueuedPublishStatus.pending);
    }

    await queue.publish(v2, relaySet: _relays, account: _bob);
    fake.ack('wss://a');
    for (final account in [_alice, _bob]) {
      final r = await waitFor(
        queue,
        v1.id,
        (r) => r.status != QueuedPublishStatus.pending,
        account: account,
      );
      expect(r.supersededBy, v2.id);
    }

    await queue.dispose();
  });

  test('republish pushes a superseded record once and keeps it', () async {
    fake.ack('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v2, relaySet: _relays);
    await waitFor(
      queue,
      v2.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );
    await queue.publish(v1, relaySet: _relays);

    await queue.republish(v1.id);
    final pushed = await waitFor(
      queue,
      v1.id,
      (r) => r.attempts == 1 && r.forcedRelays == null,
    );
    expect(pushed.status, QueuedPublishStatus.superseded);

    await queue.retryNow();
    await Future.delayed(const Duration(milliseconds: 20));
    expect(pushesOf(v1), 1);

    await queue.dispose();
  });

  test('an older version keeps going where no newer version heads', () async {
    fake.fail('wss://a');
    fake.fail('wss://b');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(
      v1,
      relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
    );
    await queue.publish(v2, relaySet: const UrlSet.explicit(['wss://b']));
    expect((await queue.get(v1.id))!.status, QueuedPublishStatus.pending);

    fake.ackAll(['wss://a', 'wss://b']);
    await waitFor(
      queue,
      v1.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );

    await queue.dispose();
  });

  test('newer versions cover the relays of an older one together', () async {
    fake.fail('wss://a');
    fake.fail('wss://b');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);
    final v3 = _version(createdAt: 300);

    await queue.publish(v2, relaySet: const UrlSet.explicit(['wss://a']));
    await queue.publish(v3, relaySet: const UrlSet.explicit(['wss://b']));
    await queue.publish(
      v1,
      relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
    );
    await waitFor(queue, v3.id, (r) => r.attempts >= 3);
    expect(pushesOf(v1), 0);

    fake.ackAll(['wss://a', 'wss://b']);
    final old = await waitFor(
      queue,
      v1.id,
      (r) => r.status == QueuedPublishStatus.superseded,
    );
    expect(old.supersededBy, v3.id);
    expect(pushesOf(v1), 0);

    await queue.dispose();
  });

  test('a relay set still to resolve covers only the same set', () async {
    fake.fail('wss://a');
    final queue = newQueue(
      relayListFn: (_, _) async => const UrlListLookup.unavailable('offline'),
    );
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);
    final v3 = _version(createdAt: 300);

    await queue.publish(v1, relaySet: _relays);
    await queue.publish(v2, relaySet: UrlSet.outbox(v2.pubkey));
    await queue.publish(v3, relaySet: UrlSet.inbox(v3.pubkey));

    await waitFor(queue, v1.id, (r) => r.attempts >= 2);
    await waitFor(queue, v2.id, (r) => r.resolutionAttempts >= 2);

    await queue.dispose();
  });

  test('a newer version refused for good does not cover the relay', () async {
    fake.refuse('wss://a', message: 'invalid: bad tag');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v2, relaySet: _relays);
    await waitFor(queue, v2.id, (r) => r.status == QueuedPublishStatus.failed);
    final queued = await queue.publish(v1, relaySet: _relays);
    expect(queued.status, QueuedPublishStatus.pending);
    expect(queued.supersededBy, isNull);
    await waitFor(queue, v1.id, (r) => r.attempts >= 1);

    await queue.dispose();
  });
}
