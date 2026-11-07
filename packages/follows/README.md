# ndk_follows

The contact lists of [NDK](https://pub.dev/packages/ndk) ([NIP-02](https://github.com/nostr-protocol/nips/blob/master/02.md)): load the contact list of a pubkey, and follow or unfollow pubkeys, hashtags, communities and events as the logged account. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes it as `ndk.follows`, cached in the `CacheManager`:

```dart
import 'package:ndk/ndk.dart';

final contactList = await ndk.follows.getContactList(pubkey);
await ndk.follows.broadcastAddContact(otherPubkey); // as the logged account
```

## Standalone

```yaml
dependencies:
  ndk_follows: ^0.1.0
  ndk_accounts: ^0.1.0
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_follows/ndk_follows.dart';

final accounts = Accounts(const Bip340EventSignerFactory());

final follows = Follows(
  query: (filter, {required timeout}) => myRelays.query(filter, timeout),
  publish: (event, {relays}) async {
    await myRelays.publish(await accounts.sign(event), relays);
  },
  cache: myCache,
  accounts: accounts,
);

final contactList = await follows.getContactList(pubkey);
accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
await follows.broadcastAddFollowedTag('nostr');
```

`query` returns the contact list events (kind 3) matching a filter. `publish` gets the changed contact list unsigned: it signs it as the logged account and sends it to the given relays, or to the author's outbox relays when they are null. `cache` is a `ContactListCache`. `accounts` is any `AuthAccounts` from [`ndk_signer`](https://pub.dev/packages/ndk_signer), such as the `Accounts` of [`ndk_accounts`](https://pub.dev/packages/ndk_accounts).

`getContactList` answers from the cache unless `forceRefresh` is set. Before a change, a cached list older than `Follows.kRefreshContactListDuration` (10 minutes) is refreshed from the relays, so the change does not drop contacts another client added or removed since. A change needs a logged account that can sign.

More in [example/](example/) and the [follows docs](https://dart-nostr.com/usecases/follows/).

## Coming from `ndk`

`Follows` and `ContactList` keep their names, and `package:ndk/ndk.dart` still exports them. The deep imports `package:ndk/domain_layer/usecases/follows/follows.dart` and `package:ndk/domain_layer/entities/contact_list.dart` are now `package:ndk_follows/ndk_follows.dart`. `Follows` takes `query`, `publish`, `cache` and `accounts` instead of `requests`, `broadcast`, `cacheManager` and `accounts`. `ContactList.relaysFromContent` is now `UserRelayList.relaysFromNip02Content` in `ndk`.
