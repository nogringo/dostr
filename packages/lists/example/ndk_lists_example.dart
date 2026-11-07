import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_lists/ndk_lists.dart';

class MemoryNip51ListCache implements Nip51ListCache {
  final Map<String, Nip01Event> _events = {};

  @override
  Future<List<Nip01Event>> loadEvents({
    List<String>? pubKeys,
    List<int>? kinds,
  }) async => _events.values
      .where(
        (e) =>
            (pubKeys == null || pubKeys.contains(e.pubKey)) &&
            (kinds == null || kinds.contains(e.kind)),
      )
      .toList();

  @override
  Future<void> saveEvent(Nip01Event event) async => _events[event.id] = event;

  @override
  Future<void> removeEvent(String id) async => _events.remove(id);
}

/// `dart run example/ndk_lists_example.dart wss://relay.example.com <pubkey hex>`
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

  final lists = Lists(
    query: (filter, {timeout, required cacheRead}) => relayReqs
        .req(
          relays: {
            relay: [filter],
          },
          timeout: timeout,
        )
        .events
        .map((received) => received.event),
    publish: (event, {relays}) async {
      final signed = await accounts.sign(event);
      await relayPublishes.publish(signed, relays: relays ?? [relay]).done;
    },
    cache: MemoryNip51ListCache(),
    accounts: accounts,
  );

  final mutes = await lists.getPublicList(
    kind: Nip51List.kMute,
    publicKey: args[1],
  );
  print('${args[1]} mutes ${mutes?.pubKeys.length ?? 0} pubkeys');

  final followSets = await lists
      .getPublicSets(kind: Nip51List.kFollowSet, publicKey: args[1])
      .last;
  print('follow sets: ${followSets?.map((set) => set.name).join(', ')}');

  await accounts.dispose();
  await relayManager.closeAllTransports();
}
