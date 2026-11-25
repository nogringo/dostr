import 'dart:async';

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

  Future<void> settle() => Future.delayed(const Duration(milliseconds: 30));

  test('cancel stops the retries of a pending record', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final event = makeEvent();

    await queue.broadcast(event, relaySet: _relays);
    await waitFor(queue, event.id, (r) => r.attempts >= 1);
    final cancelled = (await queue.cancel(event.id))!;
    expect(cancelled.status, BroadcastStatus.cancelled);
    expect(cancelled.cancelledAt, isNotNull);

    await settle();
    final pushes = fake.calls.length;
    await queue.retryNow();
    await settle();
    expect(fake.calls.length, pushes);
    expect(await queue.watchPending().first, isEmpty);
    expect(await queue.listAll(), hasLength(1));

    await queue.dispose();
  });

  test('cancel drops an unresolved relay set', () async {
    var lookups = 0;
    final queue = newQueue(
      relayListFn: (_, _) async {
        lookups++;
        return const UrlListLookup.unavailable('offline');
      },
    );
    final event = makeEvent();

    await queue.broadcast(event, relaySet: UrlSet.outbox(event.pubkey));
    final cancelled = (await queue.cancel(event.id))!;
    expect(cancelled.status, BroadcastStatus.cancelled);
    expect(cancelled.pendingRelaySet, isNull);

    await settle();
    final seen = lookups;
    await queue.retryNow();
    await settle();
    expect(lookups, seen);
    expect(fake.calls, isEmpty);

    await queue.dispose();
  });

  test('an attempt in flight completes and keeps its acks', () async {
    fake.gate = Completer<Map<RelayUrl, RelayPublishOutcome>>();
    final queue = newQueue();
    final event = makeEvent();

    await queue.broadcast(event, relaySet: _relays);
    await waitFor(queue, event.id, (_) => fake.calls.isNotEmpty);
    await queue.cancel(event.id);
    fake.gate!.complete({
      RelayUrl.parse('wss://a'): const RelayPublishOutcome.accepted(),
    });

    final record = await waitFor(queue, event.id, (r) => r.attempts == 1);
    expect(record.status, BroadcastStatus.cancelled);
    expect(record.ackedRelays, ['wss://a']);
    expect(record.deliveredAt, isNotNull);

    await queue.dispose();
  });

  test('a settled record keeps its status', () async {
    fake.ack('wss://a');
    final queue = newQueue();
    final event = makeEvent();

    await queue.broadcast(event, relaySet: _relays);
    await waitFor(queue, event.id, (r) => r.deliveredAt != null);
    final record = (await queue.cancel(event.id))!;
    expect(record.status, BroadcastStatus.delivered);
    expect(record.cancelledAt, isNull);

    await queue.dispose();
  });

  test('broadcast reopens a cancelled record', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final event = makeEvent();

    await queue.broadcast(event, relaySet: _relays);
    await queue.cancel(event.id);
    fake.ack('wss://a');
    final reopened = await queue.broadcast(event, relaySet: _relays);
    expect(reopened.status, BroadcastStatus.pending);

    final record = await waitFor(
      queue,
      event.id,
      (r) => r.status == BroadcastStatus.delivered,
    );
    expect(record.cancelledAt, isNull);

    await queue.dispose();
  });

  test('rebroadcast pushes a cancelled record once and keeps it', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final event = makeEvent();

    await queue.broadcast(event, relaySet: _relays);
    await waitFor(queue, event.id, (r) => r.attempts >= 1);
    await queue.cancel(event.id);
    await settle();
    final attempts = (await queue.get(event.id))!.attempts;

    await queue.rebroadcast(event.id);
    final pushed = await waitFor(
      queue,
      event.id,
      (r) => r.attempts == attempts + 1 && r.forcedRelays == null,
    );
    expect(pushed.status, BroadcastStatus.cancelled);

    await settle();
    expect((await queue.get(event.id))!.attempts, attempts + 1);

    await queue.dispose();
  });

  test('cancel selects the record by account', () async {
    fake.fail('wss://a');
    final queue = newQueue();
    final event = makeEvent();

    await queue.broadcast(event, relaySet: _relays, account: _alice);
    await queue.broadcast(event, relaySet: _relays, account: _bob);
    await queue.cancel(event.id, account: _alice);

    final alice = (await queue.get(event.id, account: _alice))!;
    final bob = (await queue.get(event.id, account: _bob))!;
    expect(alice.status, BroadcastStatus.cancelled);
    expect(bob.status, BroadcastStatus.pending);
    expect(await queue.cancel(event.id), isNull);

    await queue.dispose();
  });
}
