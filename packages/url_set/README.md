# dostr_url_set

Relay and Blossom server sets for Nostr, described rather than listed.

Code often has to decide where something goes before it can look anything up: "my write relays", "the DM relays of these recipients", "my Blossom servers, or these defaults if I have none".
A `UrlSet` stores that intent as a small tree that serializes to JSON, so it can sit in a queue record and be resolved later, when the network is back.

This package holds the type and its resolver, in pure Dart with no dependency.
It does not read lists from relays: you pass the lookup.

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
| `UrlSet.first(count, set)` | the first `count` distinct URLs of `set` |

Every leaf reads the list of one account.
Combine several with `union`, such as for a reply, which goes to the write relays of its author and the read relays of everyone it tags:

```dart
UrlSet.union([UrlSet.outbox(me), for (final p in tagged) UrlSet.inbox(p)])
```

A union flattens its URLs and forgets which account named each.
A gift wrap belongs on the DM relays of its own recipient only, so resolve one `UrlSet.dm` per recipient, never a union of them: the relays of the others would hold a wrap they have no use for.

Relays and Blossom servers share one type.
A consumer checks `set.kinds` and rejects the leaves it cannot use: a broadcast queue has no use for Blossom servers, and a blob upload queue none for DM relays.

## Resolving

`resolveUrlSet` takes a `UrlListFn`, which looks up one list of one account:

```dart
import 'package:dostr_url_set/dostr_url_set.dart';

Future<UrlListLookup> lookup(String pubkey, UrlListKind kind) async =>
    const UrlListLookup.notFound();

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
  case UrlsUnavailable(:final lists, :final urls):
    print('send to $urls, try $lists again later');
}
```

Every lookup ends in one of three states:

- `found`: the list exists. It may be empty.
- `notFound`: at least one relay answered (EOSE) and none holds the list.
- `unavailable`: no relay answered, so nothing is known.

The lookup finds where a list is published.
DM, private and Blossom lists live on their owner's NIP-65 write relays: while those stay unknown, a list that no relay holds is `unavailable`, not `notFound`.

Resolution follows from that:

- A union is unavailable as soon as one of its parts is.
- A fallback treats `notFound` as empty and moves on, but stops on `unavailable`. An offline device never falls through to the defaults while the real list might exist.
- Each `(pubkey, kind)` pair is looked up once per resolution.

`UrlsUnavailable.lists` names each unavailable list as an `UnavailableUrlList`, with its pubkey, kind and reason.
`UrlsUnavailable.urls` is what the set resolves to with those lists counted as empty, a fallback still stopping at them: where to send now, while the rest waits.

`urls` keeps tree order and is not deduplicated or normalized: that is up to the consumer.
`UrlSet.first` alone counts each URL once, compared as written, so `wss://a` and `wss://a/` still count as two.

Lookups and resolutions are equal when they hold the same URLs and lists, and `toString` shows them.

## Watching

`resolveUrlSet` waits for every list, so one silent relay holds back the whole set.
`watchUrlSet` gives the URLs as the lists arrive, so a request can ask a relay as soon as a list names it.
It takes a `UrlListWatchFn`, which emits each newer version of a list as `found`, or ends with `notFound` or `unavailable`:

```dart
final asked = <String>{};
await for (final snapshot in watchUrlSet(UrlSet.dm(pubkey), watch)) {
  for (final url in snapshot.urls) {
    if (asked.add(url)) print('ask $url');
  }
  if (snapshot.done) print('ended: ${snapshot.resolution}');
}
```

Each `UrlSetSnapshot` holds the URLs known so far and the lists found unavailable.
A later one may drop URLs: a newer version of a list replaces the one before, and a fallback moves past a set whose list turns out empty.
The last one is `done`, and its `resolution` is what `resolveUrlSet` gives with the lists as they ended.

## Storage

`toMap()` gives a JSON-compatible map and `UrlSet.fromMap()` reads it back.
The format is the one `RelaySet` used in `broadcast_queue_shim_for_ndk` 0.7.0, so queues stored by that version keep loading.
`UrlSet.first` is new: older readers reject a set that uses it.
`fromMap` throws a `FormatException` on any map it did not write, so a queue can skip a corrupt record.

Two sets are equal when they describe the same tree, so a queue can spot two records with the same target.
`toString` writes a set as the constructors that build it, such as `UrlSet.first(2, UrlSet.inbox(<pubkey>))`.

## Coming from `url_set_for_ndk`

`UrlSet`, `resolveUrlSet` and the lookup types moved here.
`UrlsUnavailable` held only a `reason` string: it now names the unavailable lists in `lists` and keeps the URLs found in `urls`, and `reason` joins the lists.
`UrlListFn` no longer takes `outboxRelays`, and `UrlListKind.onOutbox` is gone: the lookup finds the write relays of a DM, private or Blossom list itself, where the resolver looked up the NIP-65 first and passed them on.
`UrlListCheck` and `UrlListCheckStore` moved to [`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers), next to the lookups that keep them, as `LookupCheck` and `LookupCheckStore`.
`ndkUrlListFn` and `defaultIndexerRelays` are not here: [`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers) has `fetcherUrlListFn`, which builds the lookup from its fetchers, and `defaultIndexerRelays`.
