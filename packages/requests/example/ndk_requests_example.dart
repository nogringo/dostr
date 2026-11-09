import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_requests/ndk_requests.dart';

/// `dart run example/ndk_requests_example.dart <hex pubkey>`
Future<void> main(List<String> args) async {
  const bootstrapRelays = [
    'wss://purplepag.es',
    'wss://relay.primal.net',
    'wss://relay.ditto.pub',
  ];
  final cache = MemCacheManager();
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );

  final requests = Requests(
    cacheRead: CacheRead(cache),
    cacheManager: cache,
    networkEngine: JitEngine(
      relayManagerLight: relayManager,
      cache: cache,
      ignoreRelays: const [],
      bootstrapRelays: bootstrapRelays,
    ),
    relayManager: relayManager,
    eventVerifier: Bip340EventVerifier(),
    eventOutFilters: const [],
    defaultQueryTimeout: const Duration(seconds: 10),
  );

  final notes = await requests
      .query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [args.first],
          limit: 10,
        ),
      )
      .future;
  for (final note in notes) {
    print(note.content);
  }

  await requests.closeAllSubscription();
  await relayManager.closeAllTransports();
}
