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

  test('a newer version stops the retries of a pending older one', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v1, relaySet: _relays);
    await waitFor(queue, v1.id, (r) => r.attempts >= 1);
    final queued = await queue.publish(v2, relaySet: _relays);
    expect(queued.status, QueuedPublishStatus.pending);

    final old = (await queue.get(v1.id))!;
    expect(old.status, QueuedPublishStatus.superseded);
    expect(old.supersededBy, v2.id);

    await waitFor(queue, v2.id, (r) => r.attempts >= 3);
    final pushes = pushesOf(v1);
    await waitFor(queue, v2.id, (r) => r.attempts >= 6);
    expect(pushesOf(v1), pushes);
    expect((await queue.watchPending().first).map((r) => r.id), [v2.id]);
    expect(await queue.listAll(), hasLength(2));

    await queue.dispose();
  });

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

  test('an unresolved relay set of an older version is dropped', () async {
    final queue = newQueue(
      relayListFn: (_, _) async => const UrlListLookup.unavailable('offline'),
    );
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v1, relaySet: UrlSet.outbox(v1.pubkey));
    await queue.publish(v2, relaySet: UrlSet.outbox(v2.pubkey));
    var old = (await queue.get(v1.id))!;
    expect(old.status, QueuedPublishStatus.superseded);
    expect(old.pendingRelaySet, isNull);

    old = await queue.publish(v1, relaySet: UrlSet.outbox(v1.pubkey));
    expect(old.status, QueuedPublishStatus.superseded);
    expect(old.pendingRelaySet, isNull);
    expect((await queue.get(v1.id))!.pendingRelaySet, isNull);

    await queue.dispose();
  });

  test('addressable versions supersede each other per d tag', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final x1 = _version(kind: 30000, createdAt: 100, d: 'x');
    final y1 = _version(kind: 30000, createdAt: 150, d: 'y');
    final x2 = _version(kind: 30000, createdAt: 200, d: 'x');

    await queue.publish(x1, relaySet: _relays);
    await queue.publish(y1, relaySet: _relays);
    await queue.publish(x2, relaySet: _relays);

    expect((await queue.get(x1.id))!.supersededBy, x2.id);
    expect((await queue.get(y1.id))!.status, QueuedPublishStatus.pending);
    expect((await queue.get(x2.id))!.status, QueuedPublishStatus.pending);

    await queue.dispose();
  });

  test('versions with the same created_at keep the lowest id', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final versions = [
      _version(createdAt: 100, content: 'one'),
      _version(createdAt: 100, content: 'two'),
    ]..sort((a, b) => a.id.compareTo(b.id));
    final [lowest, highest] = versions;

    await queue.publish(lowest, relaySet: _relays);
    final queued = await queue.publish(highest, relaySet: _relays);

    expect(queued.supersededBy, lowest.id);
    expect((await queue.get(lowest.id))!.status, QueuedPublishStatus.pending);

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
      expect((await queue.get(event.id))!.status, QueuedPublishStatus.pending);
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
      final r = (await queue.get(v1.id, account: account))!;
      expect(r.status, QueuedPublishStatus.pending);
    }

    await queue.publish(v2, relaySet: _relays, account: _bob);
    for (final account in [_alice, _bob]) {
      final r = (await queue.get(v1.id, account: account))!;
      expect(r.supersededBy, v2.id);
    }

    await queue.dispose();
  });

  test('republish pushes a superseded record once and keeps it', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.publish(v1, relaySet: _relays);
    await waitFor(queue, v1.id, (r) => r.attempts >= 1);
    await queue.publish(v2, relaySet: _relays);
    final attempts = (await queue.get(v1.id))!.attempts;

    await queue.republish(v1.id);
    final pushed = await waitFor(
      queue,
      v1.id,
      (r) => r.attempts == attempts + 1 && r.forcedRelays == null,
    );
    expect(pushed.status, QueuedPublishStatus.superseded);

    await waitFor(queue, v2.id, (r) => r.attempts >= 4);
    expect((await queue.get(v1.id))!.attempts, attempts + 1);

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

    await queue.publish(
      v1,
      relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
    );
    await queue.publish(v2, relaySet: const UrlSet.explicit(['wss://a']));
    await queue.publish(v3, relaySet: const UrlSet.explicit(['wss://b']));

    expect((await queue.get(v1.id))!.supersededBy, v3.id);
    expect((await queue.get(v2.id))!.status, QueuedPublishStatus.pending);

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

    expect((await queue.get(v1.id))!.status, QueuedPublishStatus.pending);
    expect((await queue.get(v2.id))!.status, QueuedPublishStatus.pending);

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

    await queue.dispose();
  });
}
