import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_metadatas/ndk_metadatas.dart';

class MemorySearchCache implements SearchCache {
  final List<Nip01Event> events = [];

  @override
  Future<Iterable<Metadata>> searchMetadatas(String search, int limit) async =>
      events
          .where((e) => e.kind == Metadata.kKind)
          .map(Metadata.fromEvent)
          .where((m) => m.matchesSearch(search))
          .take(limit);

  @override
  Future<List<Nip01Event>> loadEvents({
    List<String>? ids,
    List<String>? pubKeys,
    List<int>? kinds,
    Map<String, List<String>>? tags,
    int? since,
    int? until,
    String? search,
    int? limit,
  }) async => [
    for (final e in events)
      if ((kinds == null || kinds.contains(e.kind)) &&
          (search == null || e.content.contains(search)))
        e,
  ];
}

/// `dart run example/search_example.dart wss://relay.example.com lightning`
///
/// The relay has to support NIP-50 search.
Future<void> main(List<String> args) async {
  final relay = args[0];
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final relayReqs = RelayReqs(
    relayManager: relayManager,
    eventVerifier: Bip340EventVerifier(),
  );

  final search = Search(
    query: (filter) => relayReqs
        .req(
          relays: {
            relay: [filter],
          },
        )
        .events
        .map((received) => received.event),
    cache: MemorySearchCache(),
  );

  final notes = await search.searchEvents(
    kinds: [1],
    search: args[1],
    limit: 10,
  );
  for (final note in notes) {
    print(note.content);
  }

  await relayManager.closeAllTransports();
}
