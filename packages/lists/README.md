# ndk_lists

The lists and sets of [NDK](https://pub.dev/packages/ndk) ([NIP-51](https://github.com/nostr-protocol/nips/blob/master/51.md)): load the mute list, bookmarks, relay sets, follow sets and the other NIP-51 kinds, and add or remove public and private elements as the logged account. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes it as `ndk.lists`, cached in the `CacheManager`, with the decrypted private elements kept in its decrypted payload cache:

```dart
import 'package:ndk/ndk.dart';

final mutes = await ndk.lists.getSingleNip51List(Nip51List.kMute);
await ndk.lists.addElementToSet(
  name: 'my-relays',
  tag: Nip51List.kRelay,
  value: 'wss://relay.example.com',
  kind: Nip51List.kRelaySet,
);
```

## Standalone

```yaml
dependencies:
  ndk_lists: ^0.1.0
  ndk_accounts: ^0.1.0
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_lists/ndk_lists.dart';

final accounts = Accounts(const Bip340EventSignerFactory());

final lists = Lists(
  query: (filter, {timeout, required cacheRead}) =>
      myRelays.query(filter, timeout),
  publish: (event, {relays}) async {
    await myRelays.publish(await accounts.sign(event), relays);
  },
  cache: myCache,
  accounts: accounts,
);

final followSets = lists.getPublicSets(
  kind: Nip51List.kFollowSet,
  publicKey: pubkey,
);
accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
await lists.addElementToList(
  kind: Nip51List.kBookmarks,
  tag: Nip51List.kThread,
  value: eventId,
  private: true,
);
```

`query` streams the list and set events matching a filter. `cacheRead` says whether cached events may answer too, a query without a cache of its own can ignore it. `publish` gets the changed list, or the deletion of a set, unsigned: it signs it as the logged account and sends it to the given relays, or to the author's outbox relays when they are null. `cache` is a `Nip51ListCache`. `accounts` is any `AuthAccounts` from [`ndk_auth`](https://pub.dev/packages/ndk_auth), such as the `Accounts` of [`ndk_accounts`](https://pub.dev/packages/ndk_accounts).

Private elements are encrypted to the logged account with NIP-44, and read back from NIP-44 or legacy NIP-04 content. Give `Lists` a `plaintextCache`, a `Nip51ListPlaintextCache`, to decrypt each event once, otherwise they are decrypted on every read. `getPublicList` and `getPublicSets` with a `publicKey` only return public elements.

More in [example/](example/) and the [lists docs](https://dart-nostr.com/usecases/lists/).

## Coming from `ndk`

`Lists`, `Nip51List`, `Nip51ListElement` and `Nip51Set` keep their names, and `package:ndk/ndk.dart` still exports them. The deep imports `package:ndk/domain_layer/usecases/lists/lists.dart` and `package:ndk/domain_layer/entities/nip_51_list.dart` are now `package:ndk_lists/ndk_lists.dart`. `Lists` takes `query`, `publish`, `cache`, `accounts` and an optional `plaintextCache` instead of `requests`, `cacheManager`, `broadcast`, `accounts`, `eventSignerFactory` and `decryptedEventPayloads`.
