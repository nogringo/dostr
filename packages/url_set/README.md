# dostr_url_set

Relay and Blossom server sets for Nostr, described rather than listed.

Code often has to decide where something goes before it can look anything up:
"my write relays", "the DM relays of these recipients", "my Blossom servers, or
these defaults if I have none". A `UrlSet` stores that intent as a small tree
that serializes to JSON, so it can sit in a queue record and be resolved later,
when the network is back.

This package holds the type and its resolver, in pure Dart with no dependency.
It does not read lists from relays: you pass the lookup. It also normalizes
relay urls, with `cleanRelayUrl` and `cleanRelayUrls`.

## Install

```yaml
dependencies:
  dostr_url_set: ^0.1.0
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

Every leaf reads the list of one account. Combine several with `union`:

```dart
UrlSet.union([for (final p in recipients) UrlSet.dm(p)])
```

Relays and Blossom servers share one type. A consumer checks `set.kinds` and
rejects the leaves it cannot use: a broadcast queue has no use for Blossom
servers, and a blob upload queue none for DM relays.

## Resolving

`resolveUrlSet` takes a `UrlListFn`, which looks up one list of one account:

```dart
import 'package:dostr_url_set/dostr_url_set.dart';

Future<UrlListLookup> lookup(
  String pubkey,
  UrlListKind kind,
  List<String> outboxRelays,
) async => const UrlListLookup.notFound();

final resolution = await resolveUrlSet(
  UrlSet.fallback([
    UrlSet.blossom(pubkey),
    UrlSet.explicit(['https://blossom.primal.net']),
  ]),
  lookup,
);

switch (resolution) {
  case UrlsResolved(:final urls):
    print('send to $urls');
  case UrlsUnavailable(:final reason):
    print('try again later: $reason');
}
```

Every lookup ends in one of three states:

- `found`: the list exists. It may be empty.
- `notFound`: at least one relay answered (EOSE) and none holds the list.
- `unavailable`: no relay answered, so nothing is known.

Resolution follows from that:

- A union is unavailable as soon as one of its parts is.
- A fallback treats `notFound` as empty and moves on, but stops on
  `unavailable`. An offline device never falls through to the defaults while
  the real list might exist.
- Each `(pubkey, kind)` pair is looked up once per resolution.
- DM, private and Blossom lists are published on their owner's NIP-65 write
  relays, so their NIP-65 is looked up first and its write relays are passed to
  the lookup as `outboxRelays`.

`UrlsResolved.urls` keeps tree order and is not deduplicated or normalized:
that is up to the consumer.

## Watching

`resolveUrlSet` waits for every list, so one silent relay holds back the whole
set. `watchUrlSet` gives the URLs as the lists arrive, so a request can ask a
relay as soon as a list names it. It takes a `UrlListWatchFn`, which emits each
newer version of a list as `found`, or ends with `notFound` or `unavailable`:

```dart
final asked = <String>{};
await for (final snapshot in watchUrlSet(UrlSet.dm(pubkey), watch)) {
  for (final url in snapshot.urls) {
    if (asked.add(url)) print('ask $url');
  }
  if (snapshot.done) print('ended: ${snapshot.resolution}');
}
```

Each `UrlSetSnapshot` holds the URLs known so far and the lookups found
unavailable. A later one may drop URLs: a newer version of a list replaces the
one before, and a fallback moves past a set whose list turns out empty. The
last one is `done`, and its `resolution` is what `resolveUrlSet` gives with the
lists as they ended.

A DM, private or Blossom list is watched along with the NIP-65 of its owner,
whose write relays come later as the `outboxRelays` future, so a lookup that
finds them itself starts right away.

## Remembering when a list was checked

A `UrlListCheck` says when the relays last answered a query for one list of an
account, and whether they held it. Addressable lists are told apart by their
`dTag`. A lookup keeps them in a `UrlListCheckStore`, so a list checked
recently is not asked again, and a list known to be absent stays `notFound`
instead of `unavailable` while offline.

`MemoryUrlListCheckStore` forgets everything on restart. To keep the checks,
implement `UrlListCheckStore` on your database, one check per pubkey, kind and
`dTag`: `UrlListCheck.toMap()` gives a JSON-compatible record.

## Storage

`toMap()` gives a JSON-compatible map and `UrlSet.fromMap()` reads it back.
The format is the one `RelaySet` used in `broadcast_queue_shim_for_ndk`
0.7.0, so queues stored by that version keep loading. `UrlSet.first` is
new: older readers reject a set that uses it.

## Coming from `url_set_for_ndk`

`UrlSet`, `resolveUrlSet`, the lookup types and `UrlListCheckStore` moved here
unchanged, except for the `dTag` of `UrlListCheckStore.read` and
`UrlListCheck`. `ndkUrlListFn` and `defaultIndexerRelays` are not here:
[`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers) has
`fetcherUrlListFn`, which builds the lookup from its fetchers, and
`defaultIndexerRelays`.
