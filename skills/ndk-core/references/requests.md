# Requests and publishes

## REQ on chosen relays (`RelayReqs`)

No cache, no outbox routing, no deduplication across relays.

```dart
final req = reqs.req(
  relays: {
    'wss://relay.example.com': [Filter(kinds: [1], authors: [pubkey], limit: 20)],
  },
  timeout: Duration(seconds: 10),
);
await for (final received in req.events) {
  print('${received.relayUrl}: ${received.event.content}');
}
final outcomes = await req.done; // per relay: eose, closed, notSent, disconnected, timedOut
```

- `closeOnEose: false` makes it a subscription; `req.close()` or cancelling the listener sends CLOSE.
- Without `relays`, call `req.send(url, filters)` per relay, then `req.seal()`.
- `auth: AuthPolicy.never() / allow(account) / require(account)` picks the identity (NIP-42).
- Events are verified; an event two relays hold arrives twice.

## EVENT on chosen relays (`RelayPublishes`)

```dart
final signed = await signer.sign(event);
final outcomes = await publishes
    .publish(signed, relays: ['wss://relay.example.com'])
    .done; // Map<String, RelayBroadcastResponse>
```

The event must be signed. No retry, no cache.

## Outbox model (`dostr_fetchers` + `dostr_url_set`)

```dart
final nip65 = Nip65Fetcher(reqs: reqs);
final dmRelays = DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65);
final blossomServers = BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65);
final metadata = MetadataFetcher(reqs: reqs, nip65Fetcher: nip65);

final profile = await metadata.fetch(pubkey); // also watch, lookup, fetchAll

// any filter, from the write relays of an author
final eventFetcher = EventFetcher(
  reqs: reqs,
  urlLists: fetcherUrlListWatchFn(
    nip65: nip65,
    dmRelays: dmRelays,
    blossomServers: blossomServers,
  ),
);
final fetch = eventFetcher.fetch(
  Filter(kinds: [1], authors: [alice]),
  from: UrlSet.outbox(alice),
);

// publish to own write relays and tagged pubkeys' read relays
final resolution = await resolveUrlSet(
  UrlSet.union([UrlSet.outbox(me), for (final p in tagged) UrlSet.inbox(p)]),
  fetcherUrlListFn(nip65: nip65, dmRelays: dmRelays, blossomServers: blossomServers),
);
if (resolution case UrlsResolved(:final urls)) {
  await publishes.publish(signed, relays: cleanRelayUrls(urls)).done;
}
```

`UrlSet` leaves: `explicit`, `outbox`, `inbox`, `nip65`, `dm`, `private`, `blossom`; combinators: `union`, `fallback`, `first`. It serializes with `toMap()` / `UrlSet.fromMap()`.

Lookups end `EventFound`, `EventNotFound` (a relay answered, none holds it) or `EventUnavailable` (no relay answered).
