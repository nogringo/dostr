import 'package:ndk/ndk.dart';
import 'package:ndk_core/ndk_core.dart'
    show RelayManager, WebSocketClientNostrTransportFactory;
import 'package:ndk_url_set/ndk_url_set.dart';

/// `dart run example/ndk_broadcast_queue_example.dart wss://relay.example.com`
Future<void> main(List<String> args) async {
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final relayPublishes = RelayPublishes(relayManager: relayManager);
  final cache = MemCacheManager();

  final queue = PendingBroadcastDelivery(
    store: cache,
    accounts: Accounts(const Bip340EventSignerFactory()),
    urlLists: (_, _, _) async => const UrlListLookup.notFound(),
    isEventInFlight: relayManager.isBroadcasting,
    send: (event, relayUrl, auth) async {
      final publish = relayPublishes.publish(
        event,
        relays: [relayUrl],
        auth: auth,
      );
      return (await publish.done).values.toList();
    },
  );

  final key = Bip340.generatePrivateKey();
  final note = Bip340.signEvent(
    event: Nip01Event(
      pubKey: key.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: const [],
      content: 'hello',
    ),
    privateKey: key.privateKey!,
  );
  await cache.saveEvent(note);
  await queue.enqueueSpecificRelayBroadcast(
    event: note,
    relayUrls: [args.first],
    requiresInteractiveSigning: false,
  );

  await queue.retryDueDeliveries(
    connectedRelayUrls: () => relayManager.connectedRelays.map((r) => r.url),
    reconnectRelay: (relayUrl) =>
        relayManager.reconnectRelay(relayUrl, force: true),
  );
  final delivery = await queue.loadEventDelivery(note.id);
  print('${delivery?.record.status}: ${delivery?.relayTargets.single.state}');

  await queue.stop();
  await relayManager.closeAllTransports();
}
