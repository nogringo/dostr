import 'dart:async';

import 'package:dostr_broadcast_queue/dostr_broadcast_queue.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import 'support/fake_broadcaster.dart';
import 'support/helpers.dart';

const _alice = 'alice_alice_alice_alice_alice_alice_alice_alice_alice_alice_al';
const _bob = 'bob_bob_bob_bob_bob_bob_bob_bob_bob_bob_bob_bob_bob_bob_bob_bob';

void main() {
  late Database db;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
  });

  tearDown(() async {
    await db.close();
  });

  test('same event under two pubkeys yields two independent records', () async {
    final fake = FakeBroadcaster()..ack('wss://a');
    final queue = BroadcastQueue(
      broadcastFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 5),
    );

    final event = makeEvent();
    await queue.broadcast(
      event,
      relaySet: const UrlSet.explicit(['wss://a']),
      pubkey: _alice,
    );
    await queue.broadcast(
      event,
      relaySet: const UrlSet.explicit(['wss://a']),
      pubkey: _bob,
    );

    final all = await queue.listAll();
    expect(all.length, 2);
    expect((await queue.get(event.id, pubkey: _alice))?.pubkey, _alice);
    expect((await queue.get(event.id, pubkey: _bob))?.pubkey, _bob);
    expect(await queue.get(event.id), isNull); // no unattributed record

    await queue.dispose();
  });

  test('clearLocalAccountData removes only the targeted account', () async {
    final fake = FakeBroadcaster()..ack('wss://a');
    final queue = BroadcastQueue(
      broadcastFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 5),
    );

    final e1 = makeEvent(seed: 1);
    final e2 = makeEvent(seed: 2);
    final e3 = makeEvent(seed: 3);
    await queue.broadcast(
      e1,
      relaySet: const UrlSet.explicit(['wss://a']),
      pubkey: _alice,
    );
    await queue.broadcast(
      e2,
      relaySet: const UrlSet.explicit(['wss://a']),
      pubkey: _bob,
    );
    await queue.broadcast(
      e3,
      relaySet: const UrlSet.explicit(['wss://a']),
    ); // unattributed

    await queue.clearLocalAccountData(pubkey: _alice);

    expect(await queue.get(e1.id, pubkey: _alice), isNull);
    expect(await queue.get(e2.id, pubkey: _bob), isNotNull);
    expect(await queue.get(e3.id), isNotNull);

    await queue.dispose();
  });

  test('a cleared pending entry is never retried again', () async {
    final fake = FakeBroadcaster()..fail('wss://gone');
    final queue = BroadcastQueue(
      broadcastFn: fake.fn,
      db: db,
      // Long backoff: after the first attempt the entry is not due again during
      // the test window, so any post-clear call would only come from a resurrected record.
      initialBackoff: const Duration(seconds: 30),
    );

    final event = makeEvent();
    await queue.broadcast(
      event,
      relaySet: const UrlSet.explicit(['wss://gone']),
      pubkey: _alice,
    );
    await waitFor(queue, event.id, (r) => r.attempts >= 1, pubkey: _alice);
    final callsAfterFirst = fake.calls.length;

    await queue.clearLocalAccountData(pubkey: _alice);
    await queue.retryNow();
    await queue.retryNow();
    await Future.delayed(const Duration(milliseconds: 20));

    expect(await queue.get(event.id, pubkey: _alice), isNull);
    expect(fake.calls.length, callsAfterFirst);

    await queue.dispose();
  });

  test(
    'clearing during an in-flight attempt does not resurrect the record',
    () async {
      final fake = FakeBroadcaster()
        ..gate = Completer<Map<RelayUrl, RelayPublishOutcome>>();
      final queue = BroadcastQueue(
        broadcastFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 5),
      );

      final event = makeEvent();
      await queue.broadcast(
        event,
        relaySet: const UrlSet.explicit(['wss://a']),
        pubkey: _alice,
      );

      // Wait until the attempt has handed off to the (parked) broadcaster.
      for (var i = 0; i < 400 && fake.calls.isEmpty; i++) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
      expect(fake.calls, isNotEmpty);

      await queue.clearLocalAccountData(pubkey: _alice);
      expect(await queue.get(event.id, pubkey: _alice), isNull);

      // Release the attempt: its transactional update must no-op on the now
      // absent record rather than write it back.
      fake.gate!.complete({
        RelayUrl.parse('wss://a'): const RelayPublishOutcome.accepted(),
      });
      await Future.delayed(const Duration(milliseconds: 30));

      expect(await queue.get(event.id, pubkey: _alice), isNull);
      expect(await queue.listAll(), isEmpty);

      await queue.dispose();
    },
  );

  test(
    'gift-wrap attribution is keyed by account, not the ephemeral event pubkey',
    () async {
      final fake = FakeBroadcaster()..ack('wss://a');
      final queue = BroadcastQueue(
        broadcastFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 5),
      );

      // A kind-1059 wrap: event.pubkey is an ephemeral throwaway ('e'*64),
      // unrelated to the account that queued it.
      final wrap = Nip01Event(
        pubkey: 'e' * 64,
        kind: 1059,
        tags: const [],
        content: 'sealed',
        sig: fakeSig,
      );
      await queue.broadcast(
        wrap,
        relaySet: const UrlSet.explicit(['wss://a']),
        pubkey: _alice,
      );

      // Clearing by the event's own pubkey must not touch it.
      await queue.clearLocalAccountData(pubkey: 'e' * 64);
      expect(await queue.get(wrap.id, pubkey: _alice), isNotNull);

      // Clearing by the queuing account removes it.
      await queue.clearLocalAccountData(pubkey: _alice);
      expect(await queue.get(wrap.id, pubkey: _alice), isNull);

      await queue.dispose();
    },
  );

  test(
    'clearAllLocalData wipes the store but leaves sibling stores intact',
    () async {
      final fake = FakeBroadcaster()..ack('wss://a');
      final queue = BroadcastQueue(
        broadcastFn: fake.fn,
        db: db,
        initialBackoff: const Duration(milliseconds: 5),
      );

      final other = stringMapStoreFactory.store('other');
      await other.record('keep').put(db, {'v': 1});

      await queue.broadcast(
        makeEvent(seed: 1),
        relaySet: const UrlSet.explicit(['wss://a']),
        pubkey: _alice,
      );
      await queue.broadcast(
        makeEvent(seed: 2),
        relaySet: const UrlSet.explicit(['wss://a']),
      );

      await queue.clearAllLocalData();

      expect(await queue.listAll(), isEmpty);
      expect(await other.record('keep').get(db), {'v': 1});

      await queue.dispose();
    },
  );

  test('unattributed entries survive an account-scoped clear', () async {
    final fake = FakeBroadcaster()..ack('wss://a');
    final queue = BroadcastQueue(
      broadcastFn: fake.fn,
      db: db,
      initialBackoff: const Duration(milliseconds: 5),
    );

    final event = makeEvent();
    await queue.broadcast(event, relaySet: const UrlSet.explicit(['wss://a']));

    await queue.clearLocalAccountData(pubkey: _alice);
    expect(await queue.get(event.id), isNotNull);

    // An unattributed record keeps the bare event id as its sembast key, so
    // pre-0.4.0 databases stay readable.
    final store = stringMapStoreFactory.store('broadcasts');
    expect(await store.record(event.id).exists(db), isTrue);

    await queue.dispose();
  });
}
