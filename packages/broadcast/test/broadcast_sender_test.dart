import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_broadcast/ndk_broadcast.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:test/test.dart';

// nothing listens there, so each relay fails fast but still answers
const outboxRelay = 'ws://localhost:1';
const bobInbox = 'ws://localhost:2';
const bootstrapRelay = 'ws://localhost:3';

void main() {
  late RelayManager relayManager;
  late Map<String, UrlListLookup> lists;

  BroadcastSender senderOf(MemCacheManager cache) => BroadcastSender(
    cacheManager: cache,
    urlLists: (pubkey, kind, _) async =>
        lists['${kind.name}|$pubkey'] ?? const UrlListLookup.notFound(),
    bootstrapRelays: const [bootstrapRelay],
    relayManager: relayManager,
    accounts: Accounts(const Bip340EventSignerFactory()),
    considerDonePercent: 1,
    timeout: const Duration(seconds: 5),
    saveToCache: true,
  );

  final key = Bip340.generatePrivateKey();
  Nip01Event signedNote({List<String> pTags = const []}) => Bip340.signEvent(
    event: Nip01Event(
      pubKey: key.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: [
        for (final p in pTags) ['p', p],
      ],
      content: 'note',
    ),
    privateKey: key.privateKey!,
  );

  Future<Set<String>> relaysOf(NdkBroadcastResponse response) async => {
    for (final outcome in await response.broadcastDoneFuture) outcome.relayUrl,
  };

  setUp(() {
    relayManager = RelayManager(
      nostrTransportFactory: WebSocketClientNostrTransportFactory(),
    );
    lists = {};
  });

  tearDown(() => relayManager.closeAllTransports());

  test('leaves no in-flight state behind when there is no signer', () async {
    final cache = MemCacheManager();
    final sender = senderOf(cache);
    final unsigned = Nip01Event(
      pubKey: 'pubkey',
      kind: Nip01Event.kTextNoteKind,
      tags: const [],
      content: 'note',
    );

    expect(
      () => sender.broadcast(
        nostrEvent: unsigned,
        specificRelays: const ['wss://relay.example'],
      ),
      throwsA(anything),
    );
    expect(sender.isEventInFlight(unsigned.id), isFalse);
    expect(await cache.loadEvent(unsigned.id), isNull);
  });

  test('sends to the outbox and the inboxes the event tags', () async {
    lists['outbox|${key.publicKey}'] = const UrlListLookup.found([outboxRelay]);
    lists['inbox|bob'] = const UrlListLookup.found([bobInbox]);

    final response = senderOf(
      MemCacheManager(),
    ).broadcast(nostrEvent: signedNote(pTags: ['bob']));

    expect(await relaysOf(response), {outboxRelay, bobInbox});
  });

  test('an unavailable inbox does not hold back the rest', () async {
    lists['outbox|${key.publicKey}'] = const UrlListLookup.found([outboxRelay]);
    lists['inbox|bob'] = const UrlListLookup.found([bobInbox]);
    lists['inbox|carol'] = const UrlListLookup.unavailable('offline');

    final response = senderOf(
      MemCacheManager(),
    ).broadcast(nostrEvent: signedNote(pTags: ['bob', 'carol']));

    expect(await relaysOf(response), {outboxRelay, bobInbox});
  });

  test('falls back to the bootstrap relays without a NIP-65', () async {
    final response = senderOf(
      MemCacheManager(),
    ).broadcast(nostrEvent: signedNote());

    expect(await relaysOf(response), {bootstrapRelay});
  });

  test('sends nowhere while the NIP-65 is unavailable', () async {
    lists['outbox|${key.publicKey}'] = const UrlListLookup.unavailable();

    final response = senderOf(
      MemCacheManager(),
    ).broadcast(nostrEvent: signedNote());

    expect(await relaysOf(response), isEmpty);
  });

  test('sends to the url set it is given', () async {
    final response = senderOf(MemCacheManager()).broadcast(
      nostrEvent: signedNote(pTags: ['bob']),
      urlSet: const UrlSet.explicit([bobInbox]),
    );

    expect(await relaysOf(response), {bobInbox});
  });

  test('takes specific relays or a url set, not both', () {
    expect(
      () => senderOf(MemCacheManager()).broadcast(
        nostrEvent: signedNote(),
        specificRelays: const [outboxRelay],
        urlSet: const UrlSet.explicit([bobInbox]),
      ),
      throwsArgumentError,
    );
  });
}
