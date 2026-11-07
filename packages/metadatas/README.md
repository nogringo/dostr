# ndk_metadatas

The user metadata of [NDK](https://pub.dev/packages/ndk) ([NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) kind 0): load the profile of one or many pubkeys, publish the logged account's own, and [search](#search) cached metadata by name or NIP-05, and events in the cache and on relays with [NIP-50](https://github.com/nostr-protocol/nips/blob/master/50.md). It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes it as `ndk.metadata`, cached in the `CacheManager`:

```dart
import 'package:ndk/ndk.dart';

final metadata = await ndk.metadata.loadMetadata(pubkey);
await ndk.metadata.broadcastMetadata(Metadata(name: 'alice')); // as the logged account
```

## Standalone

```yaml
dependencies:
  ndk_metadatas: ^0.1.0
  ndk_accounts: ^0.1.0
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_metadatas/ndk_metadatas.dart';

final accounts = Accounts(const Bip340EventSignerFactory());

final metadatas = Metadatas(
  query: (filter, {timeout, required cacheRead, relays}) =>
      myRelays.query(filter, relays, timeout),
  publish: (event, {relays}) async {
    await myRelays.publish(await accounts.sign(event), relays);
  },
  cache: myCache,
  accounts: accounts,
);

final metadata = await metadatas.loadMetadata(pubkey);
accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
await metadatas.broadcastMetadata(Metadata(about: 'hello nostr'));
```

`query` streams the metadata events (kind 0) matching a filter, from the given relays or the ones it picks when they are null. `cacheRead` says whether cached events may answer too, a query without a cache of its own can ignore it. `publish` gets the new metadata event unsigned: it signs it as the logged account and sends it to the given relays, or to the author's outbox relays when they are null. `cache` is a `MetadataCache`. `accounts` is any `AuthAccounts` from [`ndk_signer`](https://pub.dev/packages/ndk_signer), such as the `Accounts` of [`ndk_accounts`](https://pub.dev/packages/ndk_accounts).

`loadMetadata` answers from the cache unless `forceRefresh` is set. `loadMetadatas` asks relays only for the pubkeys it has no cached metadata for, and calls `onLoad` for each one as it arrives. `broadcastMetadata` merges the given fields over the content of the latest published metadata, so it does not drop fields another client set. It needs a logged account that can sign.

More in [example/](example/) and the [metadata docs](https://dart-nostr.com/usecases/metadata/).

## Search

`ndk` exposes it as `ndk.search`, backed by the `CacheManager`:

```dart
final profiles = await ndk.search.metadataSearch('alice');
final notes = await ndk.search.searchEvents(kinds: [1], search: 'lightning');
```

Standalone:

```dart
import 'package:ndk_metadatas/ndk_metadatas.dart';

final search = Search(
  query: (filter) => myRelays.query(filter),
  cache: myCache,
);

final profiles = await search.metadataSearch('alice');
final notes = await search.searchEvents(kinds: [1], search: 'lightning');
final cached = await search.searchEvents(search: 'lightning', cacheOnly: true);
```

`query` streams the events relays hold for a filter and ends once they are done. `cache` is a `SearchCache`.

`metadataSearch` only looks in the cache. `searchEvents` asks the cache and relays at once and returns both without duplicates, or the cache alone with `cacheOnly`. Relays only match `search` if they support NIP-50.

## Coming from `ndk`

`Metadatas` and `Metadata` keep their names, and `package:ndk/ndk.dart` still exports them. The deep imports `package:ndk/domain_layer/usecases/metadatas/metadatas.dart` and `package:ndk/domain_layer/entities/metadata.dart` are now `package:ndk_metadatas/ndk_metadatas.dart`. `Metadatas` takes `query`, `publish`, `cache` and `accounts` instead of `requests`, `broadcast`, `cacheManager` and `accounts`. `loadMetadatas` takes relay urls instead of a `RelaySet`. `METADATA_IDLE_TIMEOUT` of `package:ndk/config/metadata_defaults.dart` is now `Metadatas.kDefaultIdleTimeout`.

`Search` keeps its name, and `package:ndk/ndk.dart` still exports it. The deep import `package:ndk/domain_layer/usecases/search/search.dart` is now `package:ndk_metadatas/ndk_metadatas.dart`. `Search` takes `query` and `cache` instead of `requests` and `cacheManager`.
