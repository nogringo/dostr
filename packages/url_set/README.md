# ndk_url_set

Relay and Blossom server sets for Nostr, described rather than listed.

Code often has to decide where something goes before it can look anything up:
"my write relays", "the DM relays of these recipients", "my Blossom servers, or
these defaults if I have none". A `UrlSet` stores that intent as a small tree
that serializes to JSON, so it can sit in a queue record and be resolved later,
when the network is back.

This package holds the type and its resolver, in pure Dart with no dependency.
It does not read lists from relays: you pass the lookup.

## Install

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
import 'package:ndk_url_set/ndk_url_set.dart';

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

## Storage

`toMap()` gives a JSON-compatible map and `UrlSet.fromMap()` reads it back.
The format is the one `RelaySet` used in `broadcast_queue_shim_for_ndk`
0.7.0, so queues stored by that version keep loading.

## Coming from `url_set_for_ndk`

`UrlSet`, `resolveUrlSet` and the lookup types moved here unchanged.
[`url_set_for_ndk`](https://pub.dev/packages/url_set_for_ndk) re-exports them
and keeps `ndkUrlListFn`, `UrlListCheckStore` and `defaultIndexerRelays`.
