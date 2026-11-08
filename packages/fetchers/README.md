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
| `HomeRelayListFetcher` | 36205, `home-relays` list | `HomeRelayList.fromEvent` of `ndk_home_relays` |

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

`fetchAll(pubKeys)` and `lookupAll(pubKeys)` do the same for several accounts,
in a map by pubkey:

```dart
final profiles = await metadata.fetchAll([alice, bob]);
print(profiles[bob]?.content);
```

A lookup ends in one of three states:

- `EventFound`: the newest version, from the cache or a relay.
- `EventNotFound`: a relay answered (EOSE) and none holds the event.
- `EventUnavailable`: no relay answered, so nothing is known. An
  `OutboxFetcher` also ends there while the relay list is unavailable, since
  the relays that would hold the event are unknown.

A lookup runs until every relay answered or `timeout`, five seconds unless
given, counted from when its REQs go out, even once no one listens. Each
fetcher reuses a lookup still running, and one finished less than `maxAge`
ago, ten minutes unless given, when it has no checks.

## Batching

The pubkeys a fetcher looks up within `batchWindow`, 50 ms unless given, share
the REQs of each relay. Each filter holds up to 100 of them in `authors`, with
their number as `limit`, since a relay returns only the latest version of each.
100 is the lowest `max_limit` seen in relays' NIP-11, so a relay that clamps
`limit` still returns every author. A REQ holds up to 9 such filters, about
61 KB: under 65,535 bytes and under the 10 filters nostream accepts by default.

A relay that refuses a REQ with a CLOSED is asked again for each of its filters
alone, then for each pubkey alone, unless the CLOSED starts with
`auth-required:`, `restricted:`, `rate-limited:` or `blocked:`, which refuse a
REQ whatever its size.

`fetchAll` and `lookupAll` know their pubkeys up front: their REQs go out as
soon as each of their lookups read the cache, without waiting for the end of
`batchWindow`. An `OutboxFetcher` sends those for the relay lists the same
way, while the write relays, asked as each relay list arrives, still wait for
the window.

## Cache and checks

Without a cache, a cold start asks the relays for every list again. Give the
fetchers a `ReplaceableEventCache` and a `watch` starts on the event it holds,
then stores each newer one.

Give them a `UrlListCheckStore` from `ndk_url_set` too, and a lookup a relay
answered less than `maxAge` ago is answered from the cache alone, an absent
event included. Past `maxAge` the relays are asked again, and while none
answers the last known state holds.

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

[`ndk_home_relays`](https://pub.dev/packages/ndk_home_relays) computes the
relays every client derives for an account from a `home-relays` list, as the
Computed Home Relays NIP describes. Pass the list to `Nip65Fetcher` to also ask
them for relay lists:

```dart
import 'package:ndk_home_relays/ndk_home_relays.dart';

final homeRelayList = await HomeRelayList.fetch(verifier: verifier);
final nip65 = Nip65Fetcher(reqs: reqs, homeRelayList: homeRelayList);
```
