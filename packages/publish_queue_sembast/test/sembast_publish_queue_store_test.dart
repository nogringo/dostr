import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_publish_queue_sembast/dostr_publish_queue_sembast.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

const _relays = UrlSet.explicit(['wss://a']);

Nip01Event _event(int seed) => Nip01Event(
  pubkey: 'a' * 64,
  kind: 1,
  tags: const [],
  content: 'hello $seed',
  sig: 'f' * 128,
);

QueuedPublish _record(int seed, {String? account}) {
  final event = _event(seed);
  return QueuedPublish(
    id: event.id,
    account: account,
    event: event,
    relays: [RelayUrl.parse('wss://a'), RelayUrl.parse('wss://b')],
    pendingRelaySet: UrlSet.outbox(event.pubkey),
    ackedRelays: [RelayUrl.parse('wss://a')],
    lastErrors: {RelayUrl.parse('wss://b'): 'timed out'},
    terminalErrors: const {},
    inaccessibleAttempts: {RelayUrl.parse('wss://b'): 2},
    attempts: 2,
    firstAttemptAt: 1,
    lastAttemptAt: 2,
    nextAttemptAt: 3,
    deliveredAt: null,
    failedAt: null,
    createdAt: seed,
  );
}

/// Accepts every event once [online], leaves every relay silent before.
class _Relays {
  bool online = false;

  PublishFn get fn =>
      (event, relays, {account}) async => {
        if (online)
          for (final relay in relays)
            relay: const RelayPublishOutcome.accepted(),
      };
}

void main() {
  late DatabaseFactory factory;
  late Database db;

  setUp(() async {
    factory = newDatabaseFactoryMemory();
    db = await factory.openDatabase('queue.db');
  });

  tearDown(() => db.close());

  test('stores records and reads them back', () async {
    final store = SembastPublishQueueStore(db);
    final records = [_record(1), _record(2, account: 'b' * 64)];
    await store.put(records);

    final read = await store.readAll();
    expect(
      read.map((r) => r.toMap()),
      unorderedEquals(records.map((r) => r.toMap())),
    );
  });

  test('put replaces the record with the same key', () async {
    final store = SembastPublishQueueStore(db);
    final record = _record(1);
    await store.put([record]);
    await store.put([record.copyWith(attempts: 3)]);

    expect((await store.readAll()).single.attempts, 3);
  });

  test('delete leaves the other records and stores untouched', () async {
    final store = SembastPublishQueueStore(db);
    final other = stringMapStoreFactory.store('other');
    await other.record('keep').put(db, {'v': 1});
    final kept = _record(1);
    final dropped = _record(2, account: 'b' * 64);
    await store.put([kept, dropped]);

    await store.delete([dropped.key, 'absent']);

    expect((await store.readAll()).single.key, kept.key);
    expect(await other.record('keep').get(db), {'v': 1});
  });

  test('a queue loads what broadcast_queue_shim_for_ndk stored', () async {
    final event = _event(1);
    // An unattributed record is keyed by the bare event id, as the shim did.
    await stringMapStoreFactory.store('broadcasts').record(event.id).put(db, {
      'id': event.id,
      'pubkey': null,
      'event': event.toJson(),
      'relays': ['wss://a'],
      'ackedRelays': <String>[],
      'lastErrors': <String, String>{},
      'terminalErrors': <String, String>{},
      'inaccessibleAttempts': <String, int>{},
      'attempts': 0,
      'firstAttemptAt': null,
      'lastAttemptAt': null,
      'nextAttemptAt': 0,
      'deliveredAt': null,
      'failedAt': null,
      'createdAt': 0,
    });

    final queue = PublishQueue(
      publishFn: (_Relays()..online = true).fn,
      store: SembastPublishQueueStore(db),
    );
    await queue.retryNow();
    while ((await queue.get(event.id))?.status !=
        QueuedPublishStatus.delivered) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    await queue.dispose();
  });

  test('a queue survives a restart', () async {
    final relays = _Relays();
    PublishQueue newQueue() => PublishQueue(
      publishFn: relays.fn,
      store: SembastPublishQueueStore(db),
      initialBackoff: Duration.zero,
      maxBackoff: Duration.zero,
    );
    final first = newQueue();
    final event = _event(1);
    await first.publish(event, relaySet: _relays, account: 'b' * 64);
    await first.dispose();
    await db.close();

    db = await factory.openDatabase('queue.db');
    relays.online = true;
    final second = newQueue();
    await second.retryNow();
    while ((await second.get(event.id, account: 'b' * 64))?.status !=
        QueuedPublishStatus.delivered) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    await second.dispose();
  });
}
