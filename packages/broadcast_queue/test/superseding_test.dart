import 'package:dostr_broadcast_queue/dostr_broadcast_queue.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import 'support/fake_broadcaster.dart';
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
  late Database db;
  late FakeBroadcaster fake;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
    fake = FakeBroadcaster();
  });

  tearDown(() async {
    await db.close();
  });

  BroadcastQueue newQueue({UrlListFn? relayListFn}) => BroadcastQueue(
    broadcastFn: fake.fn,
    relayListFn: relayListFn,
    db: db,
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

    await queue.broadcast(v1, relaySet: _relays);
    await waitFor(queue, v1.id, (r) => r.attempts >= 1);
    final queued = await queue.broadcast(v2, relaySet: _relays);
    expect(queued.status, BroadcastStatus.pending);

    final old = (await queue.get(v1.id))!;
    expect(old.status, BroadcastStatus.superseded);
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

    await queue.broadcast(v2, relaySet: _relays);
    await waitFor(queue, v2.id, (r) => r.status == BroadcastStatus.delivered);
    final queued = await queue.broadcast(v1, relaySet: _relays);
    expect(queued.status, BroadcastStatus.superseded);
    expect(queued.supersededBy, v2.id);

    await queue.retryNow();
    await Future.delayed(const Duration(milliseconds: 20));
    expect(pushesOf(v1), 0);
    expect((await queue.get(v2.id))!.status, BroadcastStatus.delivered);

    await queue.dispose();
  });

  test('a delivered older version stays delivered', () async {
    fake.ack('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.broadcast(v1, relaySet: _relays);
    await waitFor(queue, v1.id, (r) => r.status == BroadcastStatus.delivered);
    await queue.broadcast(v2, relaySet: _relays);

    final old = (await queue.get(v1.id))!;
    expect(old.status, BroadcastStatus.delivered);
    expect(old.supersededBy, isNull);

    await queue.dispose();
  });

  test('an unresolved relay set of an older version is dropped', () async {
    final queue = newQueue(
      relayListFn: (_, _) async => const UrlListLookup.unavailable('offline'),
    );
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.broadcast(v1, relaySet: UrlSet.outbox(v1.pubkey));
    await queue.broadcast(v2, relaySet: UrlSet.outbox(v2.pubkey));
    var old = (await queue.get(v1.id))!;
    expect(old.status, BroadcastStatus.superseded);
    expect(old.pendingRelaySet, isNull);

    old = await queue.broadcast(v1, relaySet: UrlSet.outbox(v1.pubkey));
    expect(old.status, BroadcastStatus.superseded);
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

    await queue.broadcast(x1, relaySet: _relays);
    await queue.broadcast(y1, relaySet: _relays);
    await queue.broadcast(x2, relaySet: _relays);

    expect((await queue.get(x1.id))!.supersededBy, x2.id);
    expect((await queue.get(y1.id))!.status, BroadcastStatus.pending);
    expect((await queue.get(x2.id))!.status, BroadcastStatus.pending);

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

    await queue.broadcast(lowest, relaySet: _relays);
    final queued = await queue.broadcast(highest, relaySet: _relays);

    expect(queued.supersededBy, lowest.id);
    expect((await queue.get(lowest.id))!.status, BroadcastStatus.pending);

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
      await queue.broadcast(event, relaySet: _relays);
    }

    for (final event in [...notes, ...lists]) {
      expect((await queue.get(event.id))!.status, BroadcastStatus.pending);
    }

    await queue.dispose();
  });

  test('versions supersede across accounts, the same event does not', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.broadcast(v1, relaySet: _relays, account: _alice);
    await queue.broadcast(v1, relaySet: _relays, account: _bob);
    for (final account in [_alice, _bob]) {
      final r = (await queue.get(v1.id, account: account))!;
      expect(r.status, BroadcastStatus.pending);
    }

    await queue.broadcast(v2, relaySet: _relays, account: _bob);
    for (final account in [_alice, _bob]) {
      final r = (await queue.get(v1.id, account: account))!;
      expect(r.supersededBy, v2.id);
    }

    await queue.dispose();
  });

  test('rebroadcast pushes a superseded record once and keeps it', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.broadcast(v1, relaySet: _relays);
    await waitFor(queue, v1.id, (r) => r.attempts >= 1);
    await queue.broadcast(v2, relaySet: _relays);
    final attempts = (await queue.get(v1.id))!.attempts;

    await queue.rebroadcast(v1.id);
    final pushed = await waitFor(
      queue,
      v1.id,
      (r) => r.attempts == attempts + 1 && r.forcedRelays == null,
    );
    expect(pushed.status, BroadcastStatus.superseded);

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

    await queue.broadcast(
      v1,
      relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
    );
    await queue.broadcast(v2, relaySet: const UrlSet.explicit(['wss://b']));
    expect((await queue.get(v1.id))!.status, BroadcastStatus.pending);

    fake.ackAll(['wss://a', 'wss://b']);
    await waitFor(queue, v1.id, (r) => r.status == BroadcastStatus.delivered);

    await queue.dispose();
  });

  test('newer versions cover the relays of an older one together', () async {
    fake.fail('wss://a');
    fake.fail('wss://b');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);
    final v3 = _version(createdAt: 300);

    await queue.broadcast(
      v1,
      relaySet: const UrlSet.explicit(['wss://a', 'wss://b']),
    );
    await queue.broadcast(v2, relaySet: const UrlSet.explicit(['wss://a']));
    await queue.broadcast(v3, relaySet: const UrlSet.explicit(['wss://b']));

    expect((await queue.get(v1.id))!.supersededBy, v3.id);
    expect((await queue.get(v2.id))!.status, BroadcastStatus.pending);

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

    await queue.broadcast(v1, relaySet: _relays);
    await queue.broadcast(v2, relaySet: UrlSet.outbox(v2.pubkey));
    await queue.broadcast(v3, relaySet: UrlSet.inbox(v3.pubkey));

    expect((await queue.get(v1.id))!.status, BroadcastStatus.pending);
    expect((await queue.get(v2.id))!.status, BroadcastStatus.pending);

    await queue.dispose();
  });

  test('a newer version refused for good does not cover the relay', () async {
    fake.refuse('wss://a', message: 'invalid: bad tag');
    final queue = newQueue();
    final v1 = _version(createdAt: 100);
    final v2 = _version(createdAt: 200);

    await queue.broadcast(v2, relaySet: _relays);
    await waitFor(queue, v2.id, (r) => r.status == BroadcastStatus.failed);
    final queued = await queue.broadcast(v1, relaySet: _relays);
    expect(queued.status, BroadcastStatus.pending);
    expect(queued.supersededBy, isNull);

    await queue.dispose();
  });
}
