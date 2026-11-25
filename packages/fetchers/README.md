# dostr_fetchers

Fetches the lists a Nostr account publishes about itself from the relays where NIP-65 puts them, on top of `dostr_core`: its metadata, relay list, DM relays, private relays, Blossom servers and `home-relays` list.

Each fetcher asks the account's write relays as soon as its relay list arrives, and a few indexer relays meanwhile.
It hands over every newer version as it comes, and tells a list no relay holds from one no relay answered for.

## Install

```yaml
dependencies:
  dostr_fetchers: ^0.1.0
```

## Fetchers

| Fetcher | Kind | Read it with |
|---|---|---|
| `Nip65Fetcher` | 10002, NIP-65 relay list | `writeRelaysOf`, `readRelaysOf`, `allRelaysOf` |
| `MetadataFetcher` | 0, metadata | |
| `DmRelaysFetcher` | 10050, NIP-17 DM relays | `dmRelaysOf` |
| `PrivateRelaysFetcher` | 10013, NIP-37 private relays | `relaysOf`, then `privateRelaysOf` for a content decrypted elsewhere |
| `BlossomServersFetcher` | 10063, BUD-03 Blossom servers | `blossomServersOf` |
| `HomeRelayListFetcher` | 36205, `home-relays` list | `HomeRelayList.fromEvent` of `dostr_home_relays` |

`Nip65Fetcher` asks its `relays`, `defaultIndexerRelays` unless given, and the account's home relays when it has a `homeRelayList`.
The others extend `OutboxFetcher`: they ask the write relays their `nip65Fetcher` finds, and their `relays` while the relay list is on its way.
Give them all the same `Nip65Fetcher` and they share its lookups.
All of them extend `ReplaceableFetcher`, so code that reads any of them can take that type.
For another replaceable or addressable kind, create an `OutboxFetcher` with its `kind` and `dTag`.

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';

final relayManager = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relayManager,
  eventVerifier: Bip340EventVerifier(),
);
final nip65 = Nip65Fetcher(reqs: reqs);
final metadata = MetadataFetcher(reqs: reqs, nip65Fetcher: nip65);

await for (final profile in metadata.watch(pubkey)) {
  print(profile.content);
}
```

Every fetcher reads one account three ways:

- `watch(pubkey)`: each version newer than the ones before it, as it arrives.
- `fetch(pubkey)`: the newest version, or null if no relay has one.
- `lookup(pubkey)`: how the lookup ended, as an `EventLookup`.

`fetchAll(pubkeys)` and `lookupAll(pubkeys)` do the same for several accounts, in a map by pubkey:

```dart
final profiles = await metadata.fetchAll([alice, bob]);
print(profiles[bob]?.content);
```

A lookup ends in one of three states:

- `EventFound`: the newest version, from the cache or a relay.
- `EventNotFound`: a relay answered (EOSE) and none holds the event.
- `EventUnavailable`: no relay answered, so nothing is known. An `OutboxFetcher` also ends there while the relay list is unavailable, since the relays that would hold the event are unknown.

A lookup runs until every relay answered or `timeout`, five seconds unless given, counted from when its REQs go out, even once no one listens.
Each fetcher reuses a lookup still running, and one finished less than `maxAge` ago, ten minutes unless given, when it has no checks.

## Batching

The pubkeys a fetcher looks up within `batchWindow`, 50 ms unless given, share the REQs of each relay.
Each filter holds up to 100 of them in `authors`, with their number as `limit`, since a relay returns only the latest version of each. 100 is the lowest `max_limit` seen in relays' NIP-11, so a relay that clamps `limit` still returns every author.
A REQ holds up to 9 such filters, about 61 KB: under 65,535 bytes and under the 10 filters nostream accepts by default.

A relay that refuses a REQ with a CLOSED is asked for one of its pubkeys alone.
If it answers, the size was the problem: it is asked again for each of the other filters alone, then for each pubkey alone.
If it refuses that one too, the refusal stands for every pubkey of the REQ.
A CLOSED that starts with `auth-required:`, `restricted:`, `rate-limited:` or `blocked:` refuses a REQ whatever its size, so it stands for every pubkey at once.

`fetchAll` and `lookupAll` know their pubkeys up front: their REQs go out as soon as each of their lookups read the cache, without waiting for the end of `batchWindow`.
An `OutboxFetcher` sends those for the relay lists the same way, while the write relays, asked as each relay list arrives, still wait for the window.

## Cache and checks

Without a cache, a cold start asks the relays for every list again.
Give the fetchers a `ReplaceableEventCache` and a `watch` starts on the event it holds, then stores each newer one.

Give them a `LookupCheckStore` too, and a lookup a relay answered less than `maxAge` ago is answered from the cache alone, an absent event included.
Past `maxAge` the relays are asked again, and while none answers the last known state holds.

A `LookupCheck` says when the relays last answered a query for one replaceable event of an account, and whether they held it.
Addressable events are told apart by their `dTag`.

`MemoryLookupCheckStore` forgets everything on restart.
To keep the checks, implement `LookupCheckStore` on your database, one check per pubkey, kind and `dTag`: `LookupCheck.toMap()` gives a JSON-compatible record.

## Private relays

A NIP-37 private relay list, kind 10013, holds its `relay` tags encrypted to its owner with NIP-44, so only the owner's signer reads them.
`PrivateRelaysFetcher` fetches it from the owner's write relays like the other lists, and `relaysOf` decrypts it with the signer `signerOf` gives for the owner, such as `Accounts.getAccount` of `dostr_accounts`:

```dart
final privateRelays = PrivateRelaysFetcher(
  reqs: reqs,
  nip65Fetcher: nip65,
  signerOf: accounts.getAccount,
);
final list = await privateRelays.fetch(pubkey);
if (list != null) print(await privateRelays.relaysOf(list));
```

`relaysOf` puts no timeout on the signer, which may be waiting for its user.
It throws a `PrivateRelaysDecryptionException` when the owner has no signer here that can decrypt, or the signer fails.

Each call asks the signer to decrypt, which prompts the user of a remote signer such as a NIP-46 bunker.
Wrap the signers in a `CachedNostrSigner` of [`dostr_signer`](https://pub.dev/packages/dostr_signer), and each version of a list asks once, restarts included with a persistent `DecryptionCache`.

## Resolving a `UrlSet`

`fetcherUrlListFn` reads the lists of a [`dostr_url_set`](https://pub.dev/packages/dostr_url_set) `UrlSet` with these fetchers, cache and checks included:

```dart
import 'package:dostr_url_set/dostr_url_set.dart';

final lists = fetcherUrlListFn(
  nip65: nip65,
  dmRelays: DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65),
  blossomServers: BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65),
);
final resolution = await resolveUrlSet(UrlSet.dm(bob), lists);
```

`dmRelays` and `blossomServers` must find the write relays with `nip65`.
Pass a `PrivateRelaysFetcher` as `privateRelays`, with the same `nip65`, to read `UrlSet.private` too: a list its owner has no signer here to decrypt is `unavailable`, so the set is resolved again later.
Without it, a private relay list throws an `UnsupportedError`.

`resolveUrlSet` waits for every list.
To ask a relay as soon as a list names it, watch the set with `fetcherUrlListWatchFn`, which takes the same fetchers and gives each version of a list they find:

```dart
final watch = fetcherUrlListWatchFn(
  nip65: nip65,
  dmRelays: dmRelays,
  blossomServers: blossomServers,
);
await for (final snapshot in watchUrlSet(UrlSet.dm(bob), watch)) {
  print(snapshot.urls);
}
```

A DM list found on the indexers then comes before the NIP-65 lookup ends.
Each version of a private relay list comes once decrypted.

## Fetching any filter

`EventFetcher` asks the relays a `UrlSet` resolves to for the events of any filter.
Each relay is asked as soon as a list names it, with its own REQ and timeout, so the defaults of a fallback reached late still get their full time:

```dart
final nip65 = Nip65Fetcher(reqs: reqs);
final eventFetcher = EventFetcher(
  reqs: reqs,
  urlLists: fetcherUrlListWatchFn(
    nip65: nip65,
    dmRelays: DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65),
    blossomServers: BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65),
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

`urlLists` reads the lists the set names, here the NIP-65 of `alice`.
`EventFetcher` does not build these fetchers itself: give it the ones the rest of the app uses, so each list is looked up once and kept in one cache.

`events` gives each matching event once, as soon as a relay sends it, and a listener that comes late first gets those that came before it.
`done` says how the fetch ended: the events, what each relay did, and the lists that were unavailable.
`complete` is true only when every list was available and every relay sent its EOSE, so an empty result is then known to be empty.
Each relay applies the filter's `limit` on its own.

## Home relays

[`dostr_home_relays`](https://pub.dev/packages/dostr_home_relays) computes the relays every client derives for an account from a `home-relays` list, as the Computed Home Relays NIP describes.
Pass the list to `Nip65Fetcher` to also ask them for relay lists:

```dart
import 'package:dostr_home_relays/dostr_home_relays.dart';

final homeRelayList = await HomeRelayList.fetch(verifier: verifier);
final nip65 = Nip65Fetcher(reqs: reqs, homeRelayList: homeRelayList);
```
