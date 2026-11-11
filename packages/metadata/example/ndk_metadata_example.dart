import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_metadata/ndk_metadata.dart';

class MemoryMetadataCache implements MetadataCache {
  final Map<String, Nip01Event> _metadatas = {};

  @override
  Future<Metadata?> loadMetadata(String pubKey) async {
    final event = _metadatas[pubKey];
    return event == null ? null : Metadata.fromEvent(event);
  }

  @override
  Future<void> saveEvent(Nip01Event event) async {
    final current = _metadatas[event.pubKey];
    if (current == null || current.createdAt < event.createdAt) {
      _metadatas[event.pubKey] = event;
    }
  }
}

/// `dart run example/ndk_metadata_example.dart wss://relay.example.com <pubkey hex>`
Future<void> main(List<String> args) async {
  final relay = args[0];
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final relayReqs = RelayReqs(
    relayManager: relayManager,
    eventVerifier: Bip340EventVerifier(),
  );
  final relayPublishes = RelayPublishes(relayManager: relayManager);
  final accounts = Accounts(const Bip340EventSignerFactory());

  final metadatas = Metadatas(
    query: (filter, {timeout, required cacheRead, relays}) => relayReqs
        .req(
          relays: {
            for (final url in relays ?? [relay]) url: [filter],
          },
          timeout: timeout,
        )
        .events
        .map((received) => received.event),
    publish: (event, {relays}) async {
      final signed = await accounts.sign(event);
      await relayPublishes.publish(signed, relays: relays ?? [relay]).done;
    },
    cache: MemoryMetadataCache(),
    accounts: accounts,
  );

  final metadata = await metadatas.loadMetadata(args[1]);
  print('${args[1]} is ${metadata?.getName() ?? 'unknown'}');

  await accounts.dispose();
  await relayManager.closeAllTransports();
}
