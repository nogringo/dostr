# Architecture Decision Record: Relay selection

Title: Use cases describe where they read and send, and the network engines go away

## Context and Problem Statement

`Requests` and `BroadcastSender` hand every request and broadcast without explicit
relays to a `NetworkEngine`, chosen once with `NdkConfig.engine`. The engine sees
filters or a signed event, not what the caller wants, so it guesses from their shape:
`authors` go to write relays, `#p` to read relays, anything else to the bootstrap
relays. A broadcast goes to the author's write relays and to the read relays of every
`p` tag.

The guess is wrong whenever the kind decides. A gift wrap is signed by a random key, so
its author has no NIP-65 list, and its `p` tag points to the recipient's read relays
instead of their `kind:10050` relays. DM relays, Blossom servers and search all need
their own rule. The use cases that know better already bypass the engine: `Dms` passes
`specificRelays`.

The two engines also drifted apart without anyone deciding it:

| | `RELAY_SETS` (default) | `JIT` |
| --- | --- | --- |
| request without a `RelaySet` | bootstrap relays | outbox by filter shape |
| broadcast, author has no NIP-65 | every connected relay | bootstrap relays |
| `kind:3` sent to inboxes | yes | no |
| obsolete replaceable vetoed | yes | no |

Both read NIP-65 lists from the cache only and never fetch a missing one, so a list not
cached yet counts as absent and the broadcast falls back. Since `RELAY_SETS` is the
default, most apps get no outbox on requests at all.

The engine leaks into the API: `desiredCoverage`, `NdkRequest.relaySet`, `NdkEngine`,
and `ignoreRelays`, which only `JIT` reads. `JIT` keeps hidden state on connections
(`jitEngineData`). `NetworkEngine` is not an extension point either: `NdkConfig` only
takes the enum, so a custom engine means editing `init.dart`.

The fetchers in `ndk_fetchers` already pick relays per kind on `ndk_core` alone,
and fetch NIP-65 lists from the network as they arrive. They have no persistent cache,
and `fetch` returns null both when no relay answered and when none holds the list.

[`url_set_for_ndk`](https://pub.dev/packages/url_set_for_ndk) describes where something
goes instead of listing it. A `UrlSet` is a tree of `explicit`, `outbox`, `inbox`,
`nip65`, `dm`, `private` and `blossom` leaves, combined by `union` and `fallback`, that
serializes with `toMap`. `resolveUrlSet` resolves it through a `UrlListFn`, whose lookups
are `found`, `notFound` or `unavailable`, so a `fallback` never moves on while the real
list might exist. `ndkUrlListFn` reads the lists through `ndk`'s cache and keeps when
each was checked, absent ones included (`UrlListCheckStore`). The queue shims already
store their destinations this way. The package depends on `ndk`, but only for
`ndkUrlListFn`: the tree and `resolveUrlSet` import nothing.

## Main Proposal

`ndk` stays the package apps depend on, as [reduce-packages](reduce-packages.md) set
out. Its use cases describe where they read and send with a `UrlSet`, resolved through
the fetchers package, the same way `ndk_core`, `ndk_bip340`, `ndk_nip44` and `ndk_nip77`
moved out of `ndk` while `package:ndk/ndk.dart` kept its exports.

```dart
// the metadata of alice
UrlSet.union([UrlSet.outbox(alice), UrlSet.explicit(defaultIndexerRelays)]);

// a reply of alice to bob
UrlSet.union([UrlSet.outbox(alice), UrlSet.inbox(bob)]);

// a gift wrap to bob
UrlSet.dm(bob);
```

1. **Destinations.** `UrlSet` and `resolveUrlSet` move into `ndk_url_set`, a new package
   of the monorepo that depends on nothing, with the same `toMap` format so stored
   queues still load. It stays apart from the fetchers: the format it stores on devices
   must change rarely, and the queue shims need it without the network code.
   `url_set_for_ndk` re-exports it and keeps `ndkUrlListFn` until it is deprecated. The
   fetchers implement `UrlListFn` on `ndk_core` and tell `notFound` from `unavailable`.
2. **Cache.** The fetchers read and write `ndk`'s `CacheManager` through a hook, and keep
   a `UrlListCheckStore`, so a cold start does not refetch every list and a list known to
   be absent is not asked again before `maxAge`.
3. **Requests.** `Requests` takes a `UrlSet`, and the relays given explicitly today are a
   `UrlSet.explicit`. Each use case builds the set for its kind. A request asks a relay
   as soon as the list naming it arrives, so `ndk_url_set` also gets a resolver that
   streams the URLs, next to `resolveUrlSet`, which waits for every list. With no set, a
   request goes to the bootstrap relays.
4. **Broadcasts.** `BroadcastSender` takes a `UrlSet` too. Without one, a pure function
   builds it from the signed event:
   - `fallback([outbox(author), explicit(bootstrapRelays)])`, so the bootstrap relays
     are used only when the author's NIP-65 is known to be absent
   - `inbox(p)` for each `p` tag, except on a `kind:3`
   - for a gift wrap, `dm(p)` alone, since its author is a random key

   `BroadcastSender` sends to each relay once and vetoes obsolete replaceables. When the
   set is `unavailable`, `PendingBroadcastDelivery` stores it and resolves it once back
   online. A use case with its own rule passes its own set.
5. **Feeds.** Covering many authors with few relays (`RelaySets.calculateRelaySet`)
   stays, as a tool the app calls for a feed: a `UrlSet` resolves to a list of relays,
   not to the authors each one covers. It no longer runs behind every request.

### Order

Each step ships on its own:

1. `ndk_url_set`, re-exported by `url_set_for_ndk` so the queue shims keep working
2. the `UrlListFn` of the fetchers, with the cache hook and the check store
3. `BroadcastSender` and `PendingBroadcastDelivery` on a `UrlSet`, with the set built
   from the event when none is given
4. the streaming resolver, `Requests` on a `UrlSet`, and the `ndk` use cases ported to
   it (`Metadatas`, `UserRelayLists`, `Follows`, `Lists`, etc.)
5. the feed coverage as an explicit tool
6. removal of `NetworkEngine`, `JitEngine`, `RelaySetsEngine`, `NdkEngine`,
   `desiredCoverage`, `NdkRequest.relaySet`, `ignoreRelays` and `jitEngineData`, and of
   their docs (`concepts/engines`, `guides/enabling-gossip.md`, `guides/tips.md`)

## Consequences

Pro:

- Relays are picked by the code that knows the intent, and described as data: a set is
  tested without a network and stored while offline.
- An offline device never falls back to defaults while the real list might exist.
- One broadcast behaviour, which fetches the lists it is missing.
- The same description for relays and Blossom servers.
- A smaller config and request API, and no hidden state on connections.

Contra:

- Breaking: `NdkConfig.engine`, `NdkConfig.ignoreRelays`, the `desiredCoverage` and
  `relaySet` parameters, the exported `JitEngine`, and the explicit relay parameters
  unless they stay as a shorthand for `UrlSet.explicit`.
- A use case not yet ported would send to the bootstrap relays only once the engines are
  gone, which is why removal comes last.
- `ndk` depends on two more packages, `ndk_url_set` and `ndk_fetchers`.

## Open questions

- Which `defaultIndexerRelays` stays: the fetchers and `url_set_for_ndk` each have their
  own list.
- Whether a broadcast sends to the parts of its set that resolved while an unavailable
  one waits. A `union` is unavailable as soon as one of its lists is, so one unreachable
  inbox holds the whole broadcast.
- Whether the cap of `MAX_INBOX_RELAYS_TO_BROADCAST` read relays per `p` tag stays,
  which needs a node that keeps the first n URLs of a set.
- Whether `ignoreRelays` survives as a filter applied by the fetchers, or goes.
