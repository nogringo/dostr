---
icon: server
label: Relay sets
---

# Relay sets

[`ndk_url_set`](https://pub.dev/packages/ndk_url_set) describes where something goes before anything is looked up: "my write relays", "the DM relays of these recipients", "my Blossom servers, or these defaults if I have none". A `UrlSet` stores that intent as a small tree that serializes to JSON, so it can sit in a queue record and be resolved later, when the network is back.

It is pure Dart and reads no list itself: [Fetchers](fetchers.md) give it the lookups.

```yaml
dependencies:
  ndk_url_set: ^0.1.0
```

## Sets

| Constructor | Resolves to |
|---|---|
| `UrlSet.explicit(urls)` | `urls`, with no lookup |
| `UrlSet.outbox(pubkey)` | NIP-65 (kind 10002) write relays |
| `UrlSet.inbox(pubkey)` | NIP-65 read relays |
| `UrlSet.nip65(pubkey)` | every NIP-65 relay, read and write |
| `UrlSet.dm(pubkey)` | NIP-17 DM relays (kind 10050) |
| `UrlSet.private(pubkey)` | NIP-37 private relays (kind 10013), decrypted by their owner |
| `UrlSet.blossom(pubkey)` | BUD-03 Blossom servers (kind 10063) |
| `UrlSet.union(sets)` | every URL of every set |
| `UrlSet.fallback(sets)` | the first set that resolves to a non-empty list |
| `UrlSet.first(count, set)` | the first `count` URLs of `set` |

```dart
final recipients = UrlSet.union([for (final p in tagged) UrlSet.inbox(p)]);
final servers = UrlSet.fallback([
  UrlSet.blossom(pubkey),
  UrlSet.explicit(['https://blossom.example.com']),
]);
```

Relays and Blossom servers share one type. A consumer checks `set.kinds` and rejects the leaves it cannot use.

## Resolving

`resolveUrlSet` waits for every list the set names. With the fetchers of [`ndk_fetchers`](fetchers.md):

```dart
final lists = fetcherUrlListFn(
  nip65: nip65,
  dmRelays: DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65),
  blossomServers: BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65),
);

switch (await resolveUrlSet(UrlSet.outbox(pubkey), lists)) {
  case UrlsResolved(:final urls):
    print('send to $urls');
  case UrlsUnavailable(:final reason):
    print('try again later: $reason');
}
```

Every lookup ends `found` (the list exists, maybe empty), `notFound` (a relay answered and none holds it) or `unavailable` (no relay answered). A union is unavailable as soon as one of its parts is. A fallback treats `notFound` as empty and moves on, but stops on `unavailable`: an offline device never falls through to the defaults while the real list might exist.

## Watching

`watchUrlSet` gives the URLs as the lists arrive, so a request can ask a relay as soon as a list names it instead of waiting for the slowest relay:

```dart
final watch = fetcherUrlListWatchFn(
  nip65: nip65,
  dmRelays: dmRelays,
  blossomServers: blossomServers,
);

await for (final snapshot in watchUrlSet(UrlSet.dm(pubkey), watch)) {
  print(snapshot.urls);
  if (snapshot.done) print('ended: ${snapshot.resolution}');
}
```

A later snapshot may drop URLs: a newer version of a list replaces the one before. `EventFetcher` of [`ndk_fetchers`](fetchers.md#fetching-any-filter) does this for a filter.

## Storage

`toMap()` gives a JSON-compatible map and `UrlSet.fromMap()` reads it back. A `UrlListCheckStore` remembers when each list was last checked, so a recent one is not asked again and a list known to be absent stays `notFound` while offline. `MemoryUrlListCheckStore` forgets everything on restart; implement `UrlListCheckStore` on your database to keep the checks.
