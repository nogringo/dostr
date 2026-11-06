import 'package:ndk/config/broadcast_defaults.dart';
import 'package:ndk/domain_layer/usecases/broadcast/broadcast_sender.dart';
import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:test/test.dart';

// nothing listens there, so each relay fails fast but still answers
const outboxRelay = 'ws://localhost:1';
const carolInbox = 'ws://localhost:2';

void main() {
  late RelayManager relayManager;
  late Map<String, UrlListLookup> lists;
  late MemCacheManager cache;
  late PendingBroadcastDelivery pendingDelivery;
  late Broadcast broadcast;

  final key = Bip340.generatePrivateKey();
  final note = Bip340.signEvent(
    event: Nip01Event(
      pubKey: key.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: const [
        ['p', 'carol'],
      ],
      content: 'note',
    ),
    privateKey: key.privateKey!,
  );
  final carolPart = UrlSet.first(
    BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST,
    const UrlSet.inbox('carol'),
  );

  setUp(() {
    relayManager = RelayManager(
      nostrTransportFactory: WebSocketClientNostrTransportFactory(),
    );
    lists = {
      'outbox|${key.publicKey}': const UrlListLookup.found([outboxRelay]),
      'inbox|carol': const UrlListLookup.unavailable('offline'),
    };
    cache = MemCacheManager();
    final accounts = Accounts(const Bip340EventSignerFactory());
    Future<UrlListLookup> urlLists(String pubkey, UrlListKind kind, _) async =>
        lists['${kind.name}|$pubkey'] ?? const UrlListLookup.notFound();
    final sender = BroadcastSender(
      cacheManager: cache,
      urlLists: urlLists,
      bootstrapRelays: const [],
      relayManager: relayManager,
      accounts: accounts,
      considerDonePercent: 1,
      timeout: const Duration(seconds: 5),
      saveToCache: true,
    );
    pendingDelivery = PendingBroadcastDelivery(
      store: cache,
      accounts: accounts,
      urlLists: urlLists,
      isEventInFlight: sender.isEventInFlight,
      send: (event, relayUrl, auth) => sender
          .broadcast(nostrEvent: event, specificRelays: [relayUrl], auth: auth)
          .broadcastDoneFuture,
    );
    broadcast = Broadcast(
      broadcastSender: sender,
      accounts: accounts,
      cacheManager: cache,
      pendingDelivery: pendingDelivery,
    );
  });

  tearDown(() async {
    await pendingDelivery.stop();
    await relayManager.closeAllTransports();
  });

  Future<void> retry() => pendingDelivery.retryDueDeliveries(
    connectedRelayUrls: () => const [],
    reconnectRelay: (_) async => true,
  );

  test('keeps the unavailable inbox of a broadcast for later', () async {
    await broadcast.broadcast(nostrEvent: note).broadcastDoneFuture;

    final record = await cache.loadEventDeliveryRecord(note.id);
    expect(record?.status, EventDeliveryStatus.pending);
    expect(record?.unresolvedUrlSets.map((set) => set.urlSet.toMap()), [
      carolPart.toMap(),
    ]);
    expect(await cache.loadRelayDeliveryTargets(eventId: note.id), isEmpty);
  });

  test('sends to the inbox once it resolves', () async {
    await broadcast.broadcast(nostrEvent: note).broadcastDoneFuture;
    lists['inbox|carol'] = const UrlListLookup.found([carolInbox]);

    await retry();

    final record = await cache.loadEventDeliveryRecord(note.id);
    expect(record?.unresolvedUrlSets, isEmpty);
    final target = (await cache.loadRelayDeliveryTargets(
      eventId: note.id,
    )).single;
    expect(target.relayUrl, carolInbox);
    expect(target.attemptCount, 1);
  });

  test('keeps an inbox that is still unavailable', () async {
    await broadcast.broadcast(nostrEvent: note).broadcastDoneFuture;

    await retry();

    final record = await cache.loadEventDeliveryRecord(note.id);
    expect(record?.unresolvedUrlSets, hasLength(1));
    expect(await cache.loadRelayDeliveryTargets(eventId: note.id), isEmpty);
  });

  test('forgets an inbox that resolves to no relay', () async {
    await broadcast.broadcast(nostrEvent: note).broadcastDoneFuture;
    lists['inbox|carol'] = const UrlListLookup.notFound();

    await retry();

    expect(await cache.loadEventDeliveryRecord(note.id), isNull);
  });

  test('the relays of the inbox go out under the broadcast auth', () async {
    await broadcast
        .broadcast(nostrEvent: note, auth: const AuthPolicy.never())
        .broadcastDoneFuture;
    lists['inbox|carol'] = const UrlListLookup.found([carolInbox]);

    await retry();

    final target = (await cache.loadRelayDeliveryTargets(
      eventId: note.id,
    )).single;
    expect(target.authCanonical, const AuthPolicy.never().canonical);
  });

  test('a broadcast that resolves entirely is not enrolled', () async {
    lists['inbox|carol'] = const UrlListLookup.found([carolInbox]);

    await broadcast.broadcast(nostrEvent: note).broadcastDoneFuture;

    expect(await cache.loadEventDeliveryRecord(note.id), isNull);
  });

  test('retryDelivery false keeps nothing for later', () async {
    await broadcast
        .broadcast(nostrEvent: note, retryDelivery: false)
        .broadcastDoneFuture;

    expect(await cache.loadEventDeliveryRecord(note.id), isNull);
  });
}
