---
icon: broadcast
order: 99
label: Outbox model
---

# Outbox model (gossip)

The outbox model ([gossip model](https://mikedilger.com/gossip-model/)) reads an account's events from the relays it writes to, and publishes an event where its readers look: the author's write relays and the read relays of the pubkeys it tags. Both come from NIP-65 relay lists (kind 10002), which [`dostr_fetchers`](/usecases/fetchers.md) reads and [`dostr_url_set`](/usecases/relay-sets.md) turns into relays.

The examples share this setup, on top of the `reqs` of [Relay REQs](/usecases/relay-reqs.md#setup):

```dart
import 'package:dostr_fetchers/dostr_fetchers.dart';

final nip65 = Nip65Fetcher(reqs: reqs);
final dmRelays = DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65);
final blossomServers = BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65);
```

## Reading

`EventFetcher` asks the write relays of the authors as soon as their relay lists arrive:

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
```

For several authors, pass `UrlSet.union([for (final p in authors) UrlSet.outbox(p)])`.

## Publishing

Resolve the relays first, then publish there:

```dart
final lists = fetcherUrlListFn(
  nip65: nip65,
  dmRelays: dmRelays,
  blossomServers: blossomServers,
);

final resolution = await resolveUrlSet(
  UrlSet.union([
    UrlSet.outbox(signed.pubKey),
    for (final p in taggedPubkeys) UrlSet.inbox(p),
  ]),
  lists,
);

if (resolution case UrlsResolved(:final urls)) {
  await RelayPublishes(relayManager: relays)
      .publish(signed, relays: cleanRelayUrls(urls))
      .done;
}
```

`UrlsUnavailable` means a relay list could not be read: keep the event and try again later rather than publishing to fewer relays than intended. A `UrlSet` serializes to JSON for that.

## A new account

A new account has no relay list yet, so nobody can find its events. Publish its kind 10002 first, on its write relays and where the fetchers of other clients look for it: the indexer relays (`defaultIndexerRelays`) and its [home relays](/usecases/fetchers.md#home-relays).

```dart
final relayList = await signer.sign(
  Nip01Event(
    pubKey: publicKey,
    kind: 10002,
    tags: [
      ['r', 'wss://relay.example.com'],
      ['r', 'wss://inbox.example.com', 'read'],
      ['r', 'wss://outbox.example.com', 'write'],
    ],
    content: '',
  ),
);

await RelayPublishes(relayManager: relays).publish(
  relayList,
  relays: [
    'wss://relay.example.com',
    'wss://outbox.example.com',
    ...defaultIndexerRelays,
    ...homeRelayList.homeRelaysOf(publicKey),
  ],
).done;
```
