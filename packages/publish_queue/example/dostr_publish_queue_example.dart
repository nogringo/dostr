import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';

Future<void> main() async {
  final relayManager = RelayManager(
    nostrTransportFactory: webSocketTransportFactory(),
  );
  final reqs = RelayReqs(
    relayManager: relayManager,
    eventVerifier: Bip340EventVerifier(),
  );
  final nip65 = Nip65Fetcher(reqs: reqs);

  final queue = PublishQueue.withDostr(
    relayManager,
    // Keeps nothing across runs: dostr_publish_queue_sembast keeps the queue in
    // a database.
    store: MemoryPublishQueueStore(),
    relayListFn: fetcherUrlListFn(
      nip65: nip65,
      dmRelays: DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65),
      blossomServers: BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65),
    ),
  )..start();

  final signer = Bip340Signer(Bip340.generateKeyPair().privateKey);
  final event = await signer.sign(
    Nip01Event(
      pubkey: signer.publicKey,
      kind: 1,
      content: 'hello, offline-first nostr',
    ),
  );

  // Returns once the event is stored: the outbox is looked up later, offline
  // included, and a new account without one falls back to the explicit relay.
  await queue.publish(
    event,
    relaySet: UrlSet.fallback([
      UrlSet.outbox(event.pubkey),
      const UrlSet.explicit(['wss://relay.primal.net']),
    ]),
    account: signer.publicKey,
  );

  await for (final record in queue.watch(event.id, account: signer.publicKey)) {
    if (record == null || record.status == QueuedPublishStatus.pending) {
      continue;
    }
    print('${record.status.name} on ${record.ackedRelays}');
    break;
  }

  await queue.dispose();
  await relayManager.dispose();
}
