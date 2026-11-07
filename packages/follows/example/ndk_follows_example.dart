import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_follows/ndk_follows.dart';

class MemoryContactListCache implements ContactListCache {
  final Map<String, Nip01Event> _lists = {};

  @override
  Future<ContactList?> loadContactList(String pubKey) async {
    final event = _lists[pubKey];
    return event == null ? null : ContactList.fromEvent(event);
  }

  @override
  Future<void> saveEvent(Nip01Event event) async {
    final current = _lists[event.pubKey];
    if (current == null || current.createdAt < event.createdAt) {
      _lists[event.pubKey] = event;
    }
  }
}

/// `dart run example/ndk_follows_example.dart wss://relay.example.com <pubkey hex>`
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

  final follows = Follows(
    query: (filter, {required timeout}) => relayReqs
        .req(
          relays: {
            relay: [filter],
          },
          timeout: timeout,
        )
        .events
        .map((received) => received.event)
        .toList(),
    publish: (event, {relays}) async {
      final signed = await accounts.sign(event);
      await relayPublishes.publish(signed, relays: relays ?? [relay]).done;
    },
    cache: MemoryContactListCache(),
    accounts: accounts,
  );

  final contactList = await follows.getContactList(args[1]);
  print('${args[1]} follows ${contactList?.contacts.length ?? 0} pubkeys');

  await accounts.dispose();
  await relayManager.closeAllTransports();
}
