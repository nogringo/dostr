# ndk_fetchers

Fetches the lists a Nostr account publishes about itself from the relays where
NIP-65 puts them, on top of `ndk_core`: its metadata, relay list, DM relays,
Blossom servers and `home-relays` list.

Each fetcher asks the account's write relays as soon as its relay list
arrives, and a few indexer relays meanwhile. It hands over every newer version
as it comes, and tells a list no relay holds from one no relay answered for.

## Install

```yaml
dependencies:
  ndk_fetchers: ^0.1.0
```

## Fetchers

| Fetcher | Kind | Read it with |
|---|---|---|
| `Nip65Fetcher` | 10002, NIP-65 relay list | `writeRelaysOf`, `readRelaysOf`, `allRelaysOf` |
| `MetadataFetcher` | 0, metadata | |
| `DmRelaysFetcher` | 10050, NIP-17 DM relays | `dmRelaysOf` |
| `BlossomServersFetcher` | 10063, BUD-03 Blossom servers | `blossomServersOf` |
| `HomeRelayListFetcher` | 36205, `home-relays` list | `HomeRelayList.fromEvent` |

`Nip65Fetcher` asks its `relays`, `defaultIndexerRelays` unless given, and the
account's home relays when it has a `homeRelayList`. The others extend
`OutboxFetcher`: they ask the write relays their `nip65Fetcher` finds, and
their `relays` while the relay list is on its way. Give them all the same
`Nip65Fetcher` and they share its lookups.

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_fetchers/ndk_fetchers.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relayManager,
  eventVerifier: Bip340EventVerifier(),
);
final nip65 = Nip65Fetcher(reqs: reqs);
final metadata = MetadataFetcher(reqs: reqs, nip65Fetcher: nip65);

await for (final profile in metadata.watch(pubKey)) {
  print(profile.content);
}
```

Every fetcher reads one account three ways:

- `watch(pubKey)`: each version newer than the ones before it, as it arrives.
- `fetch(pubKey)`: the newest version, or null if no relay has one.
- `lookup(pubKey)`: how the lookup ended, as an `EventLookup`.

A lookup ends in one of three states:

- `EventFound`: the newest version, from the cache or a relay.
- `EventNotFound`: a relay answered (EOSE) and none holds the event.
- `EventUnavailable`: no relay answered, so nothing is known. An
  `OutboxFetcher` also ends there while the relay list is unavailable, since
  the relays that would hold the event are unknown.

A lookup runs until every relay answered or `timeout`, five seconds unless
given. `Nip65Fetcher` reuses one still running or finished less than `maxAge`
ago.

## Cache and checks

Without a cache, a cold start asks the relays for every list again. Give the
fetchers a `ReplaceableEventCache` and a `watch` starts on the event it holds,
then stores each newer one. `CacheManagerReplaceableEvents` is one on the
`CacheManager` of [`ndk_cache`](https://pub.dev/packages/ndk_cache).

Give them a `UrlListCheckStore` from `ndk_url_set` too, and a lookup a relay
answered less than `maxAge` ago is answered from the cache alone, an absent
event included. Past `maxAge` the relays are asked again, and while none
answers the last known state holds. Fetchers of one kind with different `dTag`s
need a store each.

## Resolving a `UrlSet`

`fetcherUrlListFn` reads the lists of a
[`ndk_url_set`](https://pub.dev/packages/ndk_url_set) `UrlSet` with these
fetchers, cache and checks included:

```dart
import 'package:ndk_url_set/ndk_url_set.dart';

final lists = fetcherUrlListFn(
  nip65: nip65,
  dmRelays: DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65),
  blossomServers: BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65),
);
final resolution = await resolveUrlSet(UrlSet.dm(bob), lists);
```

`dmRelays` and `blossomServers` must find the write relays with `nip65`.
Private relay lists (kind 10013) are not supported.

## Home relays

`HomeRelayList.fetch` loads the `home-relays` list nmail.li serves and checks
its signature. `homeRelaysOf(pubKey)` then gives the relays every client
computes for that account, as the Computed Home Relays NIP describes. Pass the
list to `Nip65Fetcher` to also ask them for relay lists.
