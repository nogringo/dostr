# ndk_user_relay_lists

The relay lists of users for [NDK](https://pub.dev/packages/ndk): read the relays of a pubkey from its [NIP-65](https://github.com/nostr-protocol/nips/blob/master/65.md) list, or from the content of its NIP-02 contact list when it has none, edit the list of the logged account, read the NIP-17 DM relays of a pubkey, and compute the relay set that covers a list of pubkeys. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes `UserRelayLists` as `ndk.userRelayLists` and `RelaySets` as `ndk.relaySets`:

```dart
import 'package:ndk/ndk.dart';

final relayList = await ndk.userRelayLists.getSingleUserRelayList(pubkey);
final dmRelays = await ndk.userRelayLists.getDmRelays(pubkey);
```

## Standalone

```yaml
dependencies:
  ndk_user_relay_lists: ^0.1.0
  ndk_cache: ^0.1.0
  ndk_accounts: ^0.1.0
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_user_relay_lists/ndk_user_relay_lists.dart';

final accounts = Accounts(const Bip340EventSignerFactory());

final userRelayLists = UserRelayLists(
  query: (filter, {required name, relays}) => myRelays.stream(filter, relays),
  publish: (event, {required relays}) async {
    await myRelays.publish(await accounts.sign(event), relays);
  },
  cacheManager: MemCacheManager(),
  accounts: accounts,
);

final relayList = await userRelayLists.getSingleUserRelayList(pubkey);
accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
await userRelayLists.broadcastAddNip65Relay(
  relayUrl: 'wss://relay.example.com',
  marker: ReadWriteMarker.readWrite,
  broadcastRelays: ['wss://relay.example.com'],
);
```

`query` streams the events matching a filter: `name` identifies the request, and `relays`, when not null, replaces the outbox relays. `publish` gets the edited relay list unsigned: it signs it as the logged account and sends it to the given relays. `cacheManager` keeps the lists. `accounts` is any `AuthAccounts` from [`ndk_auth`](https://pub.dev/packages/ndk_auth), such as the `Accounts` of [`ndk_accounts`](https://pub.dev/packages/ndk_accounts).

Before an edit, a cached list of the logged account older than `UserRelayLists.kRefreshUserRelayListDuration` (10 minutes) is refreshed from the relays, so the edit does not drop relays another client added or removed since.

`RelaySets.calculateRelaySet` loads the missing relay lists of some pubkeys, then picks, from the most shared relays down, the relays that each pubkey needs to reach `relayMinCountPerPubKey`, skipping the ones it cannot connect to. It needs a `RelayManager` of [`ndk_core`](https://pub.dev/packages/ndk_core).

More in [example/](example/), and in the [user relay lists](https://dart-nostr.com/usecases/user-relay-lists/) and [relay sets](https://dart-nostr.com/usecases/relay-sets/) docs.

## Coming from `ndk`

`UserRelayLists` and `RelaySets` keep their names, and `package:ndk/ndk.dart` still exports them. The deep imports `package:ndk/domain_layer/usecases/user_relay_lists/user_relay_lists.dart` and `package:ndk/domain_layer/usecases/relay_sets/relay_sets.dart` are now `package:ndk_user_relay_lists/ndk_user_relay_lists.dart`. `UserRelayLists` takes `query`, `publish`, `cacheManager` and `accounts` instead of `requests`, `cacheManager`, `broadcast` and `accounts`. `REFRESH_USER_RELAY_DURATION` of `ndk` forwards `UserRelayLists.kRefreshUserRelayListDuration`.
