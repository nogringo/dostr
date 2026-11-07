import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_broadcast/ndk_broadcast.dart';
import 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_url_set/ndk_url_set.dart';

/// `dart run example/ndk_broadcast_example.dart wss://relay.example.com`
Future<void> main(List<String> args) async {
  final relay = args[0];
  final cache = MemCacheManager();
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final accounts = Accounts(const Bip340EventSignerFactory());
  final key = Bip340.generatePrivateKey();
  accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);

  Future<UrlListLookup> urlLists(String pubkey, UrlListKind kind, _) async =>
      const UrlListLookup.notFound();

  final sender = BroadcastSender(
    cacheManager: cache,
    urlLists: urlLists,
    bootstrapRelays: [relay],
    relayManager: relayManager,
    accounts: accounts,
    considerDonePercent: 1,
    timeout: const Duration(seconds: 10),
    saveToCache: true,
  );
  final pendingDelivery = PendingBroadcastDelivery(
    store: cache,
    accounts: accounts,
    urlLists: urlLists,
    isEventInFlight: sender.isEventInFlight,
    send: (event, relayUrl, auth) => sender
        .broadcast(nostrEvent: event, specificRelays: [relayUrl], auth: auth)
        .broadcastDoneFuture,
  );
  final broadcast = Broadcast(
    broadcastSender: sender,
    accounts: accounts,
    cacheManager: cache,
    pendingDelivery: pendingDelivery,
  );

  final response = broadcast.broadcast(
    nostrEvent: Nip01Event(
      pubKey: key.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: const [],
      content: 'hello from ndk_broadcast',
    ),
  );
  for (final outcome in await response.broadcastDoneFuture) {
    print(
      '${outcome.relayUrl}: ${outcome.broadcastSuccessful ? 'OK' : outcome.msg}',
    );
  }

  await pendingDelivery.stop();
  await accounts.dispose();
  await relayManager.closeAllTransports();
}
