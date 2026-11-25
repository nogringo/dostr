import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_broadcast_queue/dostr_broadcast_queue.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

void main() {
  late Database db;
  late RelayManager relayManager;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
    relayManager = RelayManager(
      nostrTransportFactory: webSocketTransportFactory(pingInterval: null),
    );
  });

  tearDown(() async {
    await relayManager.dispose();
    await db.close();
  });

  Future<MockRelay> startRelay({
    bool requireAuthForEvents = false,
    bool answerEvents = true,
    String? rejectEventsWith,
  }) async {
    final relay = MockRelay(
      requireAuthForEvents: requireAuthForEvents,
      answerEvents: answerEvents,
      rejectEventsWith: rejectEventsWith,
    );
    await relay.start();
    addTearDown(relay.stop);
    return relay;
  }

  test('delivers to every relay', () async {
    final first = await startRelay();
    final second = await startRelay();
    final queue = BroadcastQueue.withDostr(relayManager, db: db);
    final event = makeEvent();

    await queue.broadcast(
      event,
      relaySet: UrlSet.explicit([first.url, second.url]),
    );
    final delivered = await waitFor(
      queue,
      event.id,
      (r) => r.status == BroadcastStatus.delivered,
    );
    expect(delivered.ackedRelays, unorderedEquals([first.url, second.url]));
    expect(first.events.single.id, event.id);
    expect(second.events.single.id, event.id);

    await queue.dispose();
  });

  test('a terminal refusal fails the relay', () async {
    final relay = await startRelay(rejectEventsWith: 'blocked: spam');
    final queue = BroadcastQueue.withDostr(relayManager, db: db);
    final event = makeEvent();

    await queue.broadcast(event, relaySet: UrlSet.explicit([relay.url]));
    final failed = await waitFor(
      queue,
      event.id,
      (r) => r.status == BroadcastStatus.failed,
    );
    expect(failed.terminalErrors, {relay.url: 'blocked: spam'});

    await queue.dispose();
  });

  test('a relay that does not answer times out', () async {
    final relay = await startRelay(answerEvents: false);
    final queue = BroadcastQueue.withDostr(
      relayManager,
      db: db,
      publishTimeout: const Duration(milliseconds: 100),
    );
    final event = makeEvent();

    await queue.broadcast(event, relaySet: UrlSet.explicit([relay.url]));
    final pending = await waitFor(queue, event.id, (r) => r.attempts >= 1);
    expect(pending.lastErrors, {relay.url: 'timed out'});
    expect(pending.inaccessibleAttempts, {relay.url: 1});

    await queue.dispose();
  });

  test('authenticates with the policy of the queued account', () async {
    final relay = await startRelay(requireAuthForEvents: true);
    final (:privateKey, :publicKey) = Bip340.generateKeyPair();
    final signer = Bip340Signer(privateKey);
    final queue = BroadcastQueue.withDostr(
      relayManager,
      db: db,
      authPolicyOf: (event, pubkey) =>
          pubkey == publicKey ? AuthPolicy.allow(signer) : null,
    );
    final event = makeEvent();

    await queue.broadcast(
      event,
      relaySet: UrlSet.explicit([relay.url]),
      pubkey: publicKey,
    );
    await waitFor(
      queue,
      event.id,
      (r) => r.status == BroadcastStatus.delivered,
      pubkey: publicKey,
    );
    expect(relay.clients.last.authenticatedAs, publicKey);

    await queue.dispose();
  });
}
