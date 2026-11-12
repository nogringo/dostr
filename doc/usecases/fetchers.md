---
icon: search
label: Fetchers
---

# Fetchers

[`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers) reads the lists an account publishes about itself from the relays where NIP-65 puts them, on top of [Relay REQs](relay-reqs.md). Each fetcher asks the account's write relays as soon as its relay list arrives, and a few indexer relays meanwhile. It hands over every newer version as it comes, and tells a list no relay holds from one no relay answered for.

```yaml
dependencies:
  dostr_core: ^0.11.0-dev.2
  dostr_bip340: ^0.1.0
  dostr_fetchers: ^0.1.0
```

## Setup

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';

final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relays,
  eventVerifier: Bip340EventVerifier(),
);

final nip65 = Nip65Fetcher(reqs: reqs);
final metadata = MetadataFetcher(reqs: reqs, nip65Fetcher: nip65);
final dmRelays = DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65);
final blossomServers = BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65);
```

Give every fetcher the same `Nip65Fetcher`: they then share its lookups.

| Fetcher | Kind | Read it with |
|---|---|---|
| `Nip65Fetcher` | 10002, NIP-65 relay list | `writeRelaysOf`, `readRelaysOf`, `allRelaysOf` |
| `MetadataFetcher` | 0, metadata | |
| `DmRelaysFetcher` | 10050, NIP-17 DM relays | `dmRelaysOf` |
| `BlossomServersFetcher` | 10063, BUD-03 Blossom servers | `blossomServersOf` |
| `HomeRelayListFetcher` | 36205, `home-relays` list | `HomeRelayList.fromEvent` of `dostr_home_relays` |

`Nip65Fetcher` asks its `relays`, `defaultIndexerRelays` unless given. The others ask the write relays their `nip65Fetcher` finds, and their own `relays` while the relay list is on its way.

## Reading an account

```dart
await for (final profile in metadata.watch(pubkey)) {
  print(profile.content);
}

final profiles = await metadata.fetchAll([alice, bob]);
```

- `watch(pubkey)`: each version newer than the ones before it, as it arrives.
- `fetch(pubkey)`: the newest version, or null if no relay has one.
- `lookup(pubkey)`: how the lookup ended: `EventFound`, `EventNotFound` (a relay answered and none holds the event) or `EventUnavailable` (no relay answered, so nothing is known).
- `fetchAll` and `lookupAll` do the same for several accounts, in a map by pubkey.

A lookup runs until every relay answered or `timeout`, five seconds unless given. A fetcher reuses a lookup still running, and one finished less than `maxAge` ago, ten minutes unless given.

The pubkeys looked up within `batchWindow`, 50 ms unless given, share the REQs of each relay, up to 100 authors per filter. A relay that refuses a REQ with a CLOSED is asked again with smaller ones, unless it refused for a reason the size does not change (`auth-required:`, `restricted:`, `rate-limited:`, `blocked:`).

## Cache and checks

Without a cache, a cold start asks the relays for every list again. Give the fetchers a `ReplaceableEventCache` and a `watch` starts on the event it holds, then stores each newer one. Add a `UrlListCheckStore` from [`dostr_url_set`](relay-sets.md#storage) and a list a relay answered for less than `maxAge` ago is read from the cache alone, an absent one included.

## Fetching any filter

`EventFetcher` asks the relays a [UrlSet](relay-sets.md) resolves to for the events of any filter. Each relay is asked as soon as a list names it, with its own REQ and timeout:

```dart
final eventFetcher = EventFetcher(
  reqs: reqs,
  urlLists: fetcherUrlListWatchFn(
    nip65: nip65,
    dmRelays: dmRelays,
    blossomServers: blossomServers,
  ),
);

final fetch = eventFetcher.fetch(
  Filter(kinds: [1], authors: [alice], limit: 20),
  from: UrlSet.outbox(alice),
);
fetch.events.listen(print);

final result = await fetch.done;
if (!result.complete) print('partial: ${result.unavailable}');
```

`events` gives each matching event once, as soon as a relay sends it. `complete` is true only when every list was available and every relay sent its EOSE, so an empty result is then known to be empty. Each relay applies the filter's `limit` on its own.

## Home relays

[`dostr_home_relays`](https://pub.dev/packages/dostr_home_relays) computes the relays every client derives for a pubkey from a `home-relays` list, as the Computed Home Relays NIP describes. Pass the list to `Nip65Fetcher` to also ask them for relay lists:

```dart
import 'package:dostr_home_relays/dostr_home_relays.dart';

final homeRelayList = await HomeRelayList.fetch(verifier: Bip340EventVerifier());
final nip65 = Nip65Fetcher(reqs: reqs, homeRelayList: homeRelayList);
```
