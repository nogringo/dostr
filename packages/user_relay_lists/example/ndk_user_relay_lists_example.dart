import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_user_relay_lists/ndk_user_relay_lists.dart';

/// `dart run example/ndk_user_relay_lists_example.dart wss://relay.example.com <pubkey hex>`
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

  final userRelayLists = UserRelayLists(
    query: (filter, {required name, relays}) => relayReqs
        .req(
          name: name,
          relays: {
            for (final url in relays ?? [relay]) url: [filter],
          },
        )
        .events
        .map((received) => received.event),
    publish: (event, {required relays}) async {
      final signed = await accounts.sign(event);
      await relayPublishes.publish(signed, relays: relays).done;
    },
    cacheManager: MemCacheManager(),
    accounts: accounts,
  );

  final relayList = await userRelayLists.getSingleUserRelayList(args[1]);
  if (relayList == null) {
    print('${args[1]} has no relay list');
  } else {
    for (final MapEntry(:key, :value) in relayList.relays.entries) {
      print('$key: ${value.name}');
    }
  }

  await accounts.dispose();
  await relayManager.closeAllTransports();
}
