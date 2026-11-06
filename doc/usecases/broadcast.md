---
icon: arrow-up-right
---

[!badge variant="primary" text="low level"]

## Example

```dart
  final myBroadcast = ndk.broadcast.broadcast(
      nostrEvent: Nip01Event(
        pubKey:
            '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
        kind: 1,
        tags: [],
        content: 'Hello, World!',
      ),
    );
    final result = await myBroadcast.broadcastDoneFuture;
    for (final relayResponse in result) {
      print(
          "broadcast on ${relayResponse.relayUrl}:  ${relayResponse.broadcastSuccessful}");
    }

```

## Where it goes

Without `specificRelays`, a broadcast goes to:

- the NIP-65 write relays of its author, or the bootstrap relays once the
  author is known to have no NIP-65
- the first 5 NIP-65 read relays of each `p` tag, except on a contact list
  (kind 3)
- for a gift wrap (kind 1059), only the NIP-17 DM relays of each `p` tag

NDK fetches the lists it does not have from the bootstrap relays and keeps them
in its cache. A list no relay answered for is skipped with a warning, and the
rest of the broadcast goes out. The skipped part is kept in pending delivery:
NDK looks the list up again on each retry, and once it is found, the relays it
names are retried like specific relays.

To pick the relays yourself, pass a `UrlSet`:

```dart
final myBroadcast = ndk.broadcast.broadcast(
  nostrEvent: event,
  urlSet: UrlSet.union([
    UrlSet.outbox(event.pubKey),
    UrlSet.explicit(['wss://relay.example.com']),
  ]),
);
```

## Relay authentication (NIP-42)

Some relays only accept an event from a client that authenticated. The `auth`
parameter says which identity the broadcast may be attributed to, exactly like
on [requests](/usecases/requests.md#relay-authentication-nip-42):

```dart
final myBroadcast = ndk.broadcast.broadcast(
  nostrEvent: report,
  auth: const AuthPolicy.never(),
);
```

| policy | connection | what a relay learns |
| --- | --- | --- |
| `AuthPolicy.never()` | anonymous, always | nothing. A relay that refuses the event without an identity simply does not accept it |
| `AuthPolicy.allow(a)` | anonymous, moves to one bound to `a` once the relay refuses | who you are, but only after that relay asked |
| `AuthPolicy.require(a)` | bound to `a` from the start | who you are, as soon as it sends a challenge |

Without `auth`, a broadcast reveals no identity. With an [`AuthHandler`](/concepts/nip42-auth.md#authhandler), a refused
event authenticates as its author when a registered account matches, as the
logged-in account otherwise, where the handler agrees.

The account does not have to be one NDK knows: `allow` and `require` take the
`Account` itself, so an identity you built on the spot works.

If `require` names an account that cannot sign, no connection can carry the
event. Rather than fall back to the anonymous one, which is what `require`
rules out, nothing is sent and `broadcast` itself throws
`BroadcastAuthUnavailableException`.

### Across a restart

A signer is never written to disk, only the policy is, as `never`,
`allow:<pubkey>` or `require:<pubkey>`. That matters for the background retries
described below, not for the broadcast you are awaiting.

- `never()` survives a restart whole, because it names nobody. A relay that
  refuses such an event is a final answer, so it is not retried at all.
- `allow` and `require` resolve their pubkey through the accounts NDK holds. A
  retry therefore needs that account to be registered again after a restart.
- An identity no account can sign for parks the delivery in
  `EventDeliveryStatus.needsAction` instead of going out as somebody else. You
  see it through `loadPendingDeliveries()`, and you resume it by broadcasting
  the same event again with the account in hand.

## When to use

Broadcast should be used when your use case has no broadcasting method. \
Signing is done automatically, and you can specify a custom signer just for one broadcast. \
By default, the inbox/outbox model is used for broadcasting looking at the event data (e.g. if it's a reply) you can also specify specific relays to broadcast to.

## Local-first behavior

NDK keeps delivery state for locally created events in the configured cache backend.
The queue that retries them lives in the `ndk_broadcast_queue` package, which `ndk`
depends on and re-exports.

That means:

- an event may be visible locally before every relay accepts it
- pending delivery can survive app restarts when the cache backend is persistent
- if signing is delayed by an external signer, the unsigned event can still stay queued locally
- retries can continue later when relays are reachable again
- replaceable events only keep retrying the newest visible version

With `MemCacheManager`, this state exists while the process is alive. With a persistent `CacheManager`, it also survives restarts.

## Retry behavior

Background delivery retries are not identical for every event.

Current behavior includes:

- replaceable events retry as latest-state-only delivery
- ephemeral events are not kept for retry
- some control-style events can use faster retry behavior
- relay responses classified as permanent failure stop retry for that relay target
- relay responses classified as transient failure remain retryable
- external signer flows can also be retried in the background before relay delivery continues

### Sending once without retry

`retryDelivery: false` keeps one broadcast out of pending delivery:

```dart
ndk.broadcast.broadcast(
  nostrEvent: event,
  specificRelays: ['wss://relay.example.com'],
  retryDelivery: false,
);
```

No delivery record is written for that event, so nothing retries it whatever the
relays answer, and it never shows up in `loadPendingDeliveries()`. A gossip
broadcast is only enrolled for the lists it could not look up, which this drops
too. `broadcastReaction()` and `broadcastDeletion()` take the same parameter.

To turn background retries off for the whole client instead, use
`NdkConfig(pendingDeliveryRetriesEnabled: false)`. That one keeps persisting
delivery state, it only stops replaying it.

## External signer retry behavior

When you broadcast through an external signer such as `Nip46EventSigner`,
`Nip07EventSigner`, or `Nip55EventSigner`, signing and relay delivery are treated
as separate steps.

Current behavior:

- if the signer does not complete immediately, the event can remain queued locally
- once signing succeeds later, NDK can continue relay delivery for that same event
- if the signer depends on network transport, retries are biased toward moments when the signer transport looks reachable again
- if the signer succeeds while some target relays are still offline, delivery to those relays can still continue later

In practice this means apps can treat delayed external signing as part of the same
local-first publish flow instead of having to rebuild the publish manually.

## Delivery policy

NDK uses the `DeliveryPolicy` of `ndk_broadcast_queue` for local-first broadcast retry handling.

Current policy selection is automatic:

- ephemeral events use `doNotRetry`
- deletion events use `highPriorityControl`
- replaceable and addressable events use `latestStateOnly`
- other events use `persistentEventual`

This policy is currently **not configurable** through `ndk.broadcast.broadcast()`,
`NdkConfig`, or a per-event override.

That means:

- you cannot choose a custom retry/backoff profile for one broadcast
- you cannot inject your own delivery policy classifier
- the practical way to influence policy today is through the event kind you publish
- the one per-broadcast control is `retryDelivery: false`, which skips retry entirely

Examples:

- `kind:5` deletions get faster control-style retries
- replaceable kinds only keep retrying the newest visible version
- ephemeral kinds are not persisted for background retry

## Relay targeting

Broadcast targeting can include more than author outbox relays.

Depending on the event, NDK may target:

- explicit relays
- author write relays
- inbox/read relays needed for replies and reactions

Delivery targets are tracked separately from source provenance.
