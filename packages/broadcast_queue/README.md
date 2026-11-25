# dostr_broadcast_queue

An offline-first queue for Nostr events, in front of the publishes of [`dostr_core`](https://pub.dev/packages/dostr_core).

`RelayPublishes.publish` sends a signed event to the relays you pick once, and reports what each relay did.
If the network is down, the app is backgrounded or the process is killed, the event is gone.
This queue stores the event in a [sembast](https://pub.dev/packages/sembast) database first, then keeps sending it until every relay has accepted it, refused it for good, or stayed unreachable while the device was online:

 - **Local persistence first.** `broadcast()` returns once the event is stored, before any network attempt. Delivery happens in the background and survives restarts.
 - **Full delivery.** An entry is only `delivered` once *every* targeted relay has accepted the event. A partial success keeps it pending and retries the relays still owed.
 - **Monotonic ack history.** A relay that accepted the event never un-acks, so a delivered entry never flips back to pending on a transient outage.
 - **Terminal refusals.** An `OK false` with a `blocked`, `invalid`, `mute`, `pow` or `restricted` prefix, an event too long for the relay, or a relay the `RelayManager` blocks, stops the retries on that relay and shows as `BroadcastStatus.failed`.
 - **Dead relay cutoff.** A relay unreachable for 12 consecutive online attempts is stopped for that event.
 - **Relay sets resolved offline.** Target an account's NIP-65 outbox, its recipients' inboxes, NIP-17 DM relays or NIP-37 private relays with a [`dostr_url_set`](https://pub.dev/packages/dostr_url_set) `UrlSet`, without knowing the URLs yet. The set is stored as is, resolved once online, then frozen.
 - **Superseded versions.** Queuing a new version of a replaceable or addressable event stops the retries of an older version still pending once newer versions head to all its relays.
 - **Ordered, capped publishing.** At most `maxConcurrentPublishes` entries publish at once, taken in the order they were queued, so a backlog piled up offline goes out in order.
 - **Cancellation and account-scoped clearing.** `cancel` stops one entry and keeps it in the store, `clearLocalAccountData` wipes one account's queue on logout.
 - **No auto-deletion.** Delivered entries stay in the store and can be re-broadcast later, to a freshly discovered relay for instance.

## Install

```yaml
dependencies:
  dostr_broadcast_queue: ^0.1.0
```

## Quick start

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_broadcast_queue/dostr_broadcast_queue.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:sembast/sembast_io.dart';

final db = await databaseFactoryIo.openDatabase('broadcasts.db');
final relayManager = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relayManager,
  eventVerifier: Bip340EventVerifier(),
);
final nip65 = Nip65Fetcher(reqs: reqs);

final queue = BroadcastQueue.withDostr(
  relayManager,
  db: db,
  relayListFn: fetcherUrlListFn(
    nip65: nip65,
    dmRelays: DmRelaysFetcher(reqs: reqs, nip65Fetcher: nip65),
    blossomServers: BlossomServersFetcher(reqs: reqs, nip65Fetcher: nip65),
  ),
)..start();

// Returns as soon as the event is stored. Delivery is now the queue's job.
await queue.broadcast(
  signedEvent,
  relaySet: const UrlSet.explicit([
    'wss://relay.primal.net',
    'wss://relay.ditto.pub',
  ]),
);

// Or let the queue find the author's write relays later, offline included.
await queue.broadcast(signedEvent, relaySet: UrlSet.outbox(signedEvent.pubkey));
```

The full example is in [example/dostr_broadcast_queue_example.dart](example/dostr_broadcast_queue_example.dart).

## Semantics

### `broadcast(event, {required UrlSet relaySet, String? account})`

Persists `event` and schedules an immediate attempt to the relays of `relaySet` (see [Relay sets](#relay-sets)).
`event` must be signed: the queue never signs, and `broadcast` throws an `ArgumentError` on an unsigned event.
URLs are normalized as `RelayUrl.tryParse` does, and those that are not ws or wss urls are dropped.
`broadcast` never waits on the network.
A set that needs no lookup and holds no relay throws an `ArgumentError`.

Records are keyed by the pair `(event.id, account)`.
If a record with the same pair already exists, the relay lists are merged: `deliveredAt` is kept if every relay in the merged list has already acked, otherwise the entry goes back to pending so the missing relays get the event.
A relay set that needs a lookup is merged the same way once it resolves.
Either way the entry is attempted right away and its backoff starts over.
The same event queued under a different `account` is a separate record.

`account` is optional and defaults to `null` (unattributed).
See [Account-scoped clearing](#account-scoped-clearing) for what it buys you, and [Authentication](#authentication) for the publishes.

### Relay sets

A `UrlSet` of [`dostr_url_set`](https://pub.dev/packages/dostr_url_set) describes where an event goes instead of listing URLs:

```dart
UrlSet.explicit(['wss://a', 'wss://b'])  // fixed URLs
UrlSet.outbox(pubkey)                    // NIP-65 write relays
UrlSet.nip65(pubkey)                     // every NIP-65 relay, read and write
UrlSet.inbox(pubkey)                     // NIP-65 read relays
UrlSet.dm(pubkey)                        // NIP-17 DM relays (kind 10050)
UrlSet.private(pubkey)                   // NIP-37 private relays (kind 10013)
UrlSet.union([a, b])                     // every relay of every set
UrlSet.fallback([a, b])                  // first set with at least one relay
UrlSet.first(count, set)                 // the first count relays of set
```

Every leaf reads the list of one account.
Combine several with `union`: `UrlSet.union([for (final p in recipients) UrlSet.dm(p)])`.
`UrlSet.blossom` names Blossom servers, not relays: `broadcast` rejects it with an `ArgumentError`.
Use `dm`, not `inbox`, for gift wraps.

The lookups go through the `relayListFn` you pass, usually `fetcherUrlListFn` of [`dostr_fetchers`](https://pub.dev/packages/dostr_fetchers), which reads the lists from the account's write relays and a few indexers, with its cache.
Pass it a `PrivateRelaysFetcher` as `privateRelays` to resolve `UrlSet.private`: the list is encrypted to its owner, so a lookup for an account without a signer here is unavailable and retried.
Without a `relayListFn`, only sets that need no lookup are accepted.

The set is persisted with the entry, which stays `pending` with an empty `relays` list and a non-null `pendingRelaySet`.
The worker resolves it on its next attempt and, **the first time every lookup concludes**, freezes the result into `relays` and clears `pendingRelaySet`.
Later retries push to those frozen relays and never look the lists up again.
A set that needs no lookup is resolved at enqueue time.

Each lookup ends in one of three states:

 - **found**: the list exists (it may hold no relay of the wanted kind).
 - **not found**: relays answered and none holds the list. It counts as an empty list.
 - **unavailable**: no relay answered, or the list could not be decrypted. Whether the list exists is unknown.

If any lookup the result depends on is unavailable, nothing is frozen: the entry records `resolutionError`, increments `resolutionAttempts` and retries with backoff.
This matters for `fallback`: an offline lookup never falls through to the next set, so going offline cannot lock an entry onto its fallback relays.

If the whole set resolves to no relay, the entry becomes `failed` with `resolutionError: 'relay set resolved to no relay'`.
Calling `broadcast` again with a set queues a new resolution on the same entry.

The queue never times a lookup out as a whole, so a remote signer (NIP-46, NIP-55) can wait for the user's approval as long as it takes: bound the network part in the fetchers.
`dispose` does not wait for such a lookup: the resolution is abandoned without writing and starts over on the next run.
Once frozen, private relays are stored in plain text in the queue's database.

### Replaceable and addressable events

Relays keep only the latest version of a replaceable (kind 0, 3, 10000-19999) or addressable (kind 30000-39999, per `d` tag) event: the highest `created_at`, then the lowest id.
So an older version only needs to reach the relays no newer version will.
When `broadcast` queues such an event, a record of an older version of the same address that is still pending becomes `BroadcastStatus.superseded` once the newer versions in the store, together, hold or are still headed to every relay it owes:

 - it is no longer retried, and an unresolved relay set is dropped;
 - `supersededBy` holds the id of the newest version;
 - it leaves `watchPending()` but stays in `listAll()`.

A newer version counts on the relays that acked it, and on those it is still being sent to while it is pending: a relay that refused it for good, or that a cancelled version never reached, does not count.
A relay set still to resolve only covers the same set still to resolve.
An older version that is not covered keeps going to all its relays: those that also get a newer version keep the newer one.

This spans every `account` label, since relays do not care which local account queued a version.
It holds for a version older than one already in the store too, delivered or not: covered, it is stored superseded and never sent.
Older versions that were already delivered or failed keep their status.
`rebroadcast` still forces one push of a superseded record, which stays superseded.

Edit a NIP-65 list twice offline, sending both versions to the same relays, and only the second version goes out once back online.

### Account-scoped clearing

`account` labels the local account an entry was queued under, by its pubkey, so its queue can be dropped on logout:

```dart
await queue.broadcast(event, relaySet: ..., account: myPubkey);
...
await queue.clearLocalAccountData(account: myPubkey); // wipe this account
await queue.clearAllLocalData();                      // wipe everything
```

 - It need not be `event.pubkey`. An event may be queued under an account that did not sign it (rebroadcasting someone else's note), and for a gift wrap (kind 1059) `event.pubkey` is an ephemeral throwaway key. Pass the real sending account so NIP-17 DMs and other wraps can still be cleared.
 - Leaving `account` `null` leaves the entry **unattributed**: retried like any other, keyed by the bare `event.id`, but never removed by `clearLocalAccountData`.
 - `clearLocalAccountData` removes matching entries for good, delivered or not. It is safe to call while attempts are in flight (a concurrent attempt no-ops once its record is gone), but do not `broadcast` for an account you are clearing, as an overlapping enqueue can re-create its record.
 - `get`, `watch`, `rebroadcast` and `cancel` take the same optional `account` to select which record they act on. `watchPending` and `listAll` span all accounts; filter on `QueuedBroadcast.account` for one.
 - `clearAllLocalData` empties the queue's store only; other sembast stores in the same database are untouched.

### Authentication

A relay may ask for NIP-42 authentication before it accepts an event, as private relays (NIP-37) do.
`withDostr` takes `authPolicyOf`, which gives the `AuthPolicy` of each publish from the event and the account it was queued under:

```dart
BroadcastQueue.withDostr(
  relayManager,
  db: db,
  authPolicyOf: (event, account) {
    if (event.kind == 1059 || account == null) return null;
    final signer = accounts.getAccount(account);
    return signer == null ? null : AuthPolicy.allow(signer);
  },
);
```

`AuthPolicy.allow` publishes anonymously first and authenticates once a relay refuses without an identity.
A `null` policy publishes as `dostr_core` does by default.
Never authenticate a gift wrap as its sender: that tells the recipient's relay who wrote to them.

### Connectivity

An attempt made while the device is offline does not count towards the dead relay cutoff, and is retried after `initialBackoff` without growing the backoff, so everything goes out shortly after the network is back.
The backoff only grows with the attempts that fail online, and starts over when `broadcast` queues the entry again or `rebroadcast` gives it a new relay.

Pass the platform's connectivity as `onlineSignal`, such as a stream of `connectivity_plus`, to tell the queue when the device is offline:

```dart
BroadcastQueue.withDostr(
  relayManager,
  db: db,
  onlineSignal: yourConnectivityStream, // true while online, false otherwise
);
```

While its latest value is `false`, the periodic retries pause, and the `false -> true` edge replays everything due at once.

Without `onlineSignal`, `withDostr` reads the network from the connections of the `RelayManager`: online once a public relay is connected, offline once every connection to one failed or dropped.
Loopback, private IPv4 and IPv6, and mDNS `.local` hosts are left out, so a connected dev relay does not mask an outage.
`dostr_core` closes idle connections, so having none tells nothing: this signal never pauses the periodic retries.
In a process without other open connections, an unreachable relay then looks like an offline device: it is retried every tick and never cut off.
Pass `onlineSignal` there too.

An attempt in which one of the relays answered counts as online whatever the signal says.
The default constructor without `onlineSignal` assumes it is always online.

### `retryNow()`

Forces an immediate scan of due entries, bypassing the online check.
Use it as an explicit override (e.g. when the user pulls to refresh).

### `rebroadcast(id, {String? account, String? relay})`

`ackedRelays` and `deliveredAt` are monotonic.
`rebroadcast` never rewrites the past; it queues a one-shot push via a transient `forcedRelays` override that the next attempt consumes.
It returns `null` if no such record exists.

 - `rebroadcast(id)`: schedules an immediate push to **every** relay in the entry's `relays` list, including those that already acked. Useful when you suspect a relay dropped your event. Acks and `deliveredAt` are kept regardless of the new attempt's outcome.
 - `rebroadcast(id, relay: r)`: pushes to that single relay. If `r` is new to the entry, it joins the target list, the entry goes back to pending until `r` acks and its backoff starts over. If `r` was already there, the historical state is kept. A `relay` that is not a ws or wss url throws an `ArgumentError`.

### `cancel(id, {String? account})`

Stops the retries of a pending entry.
It becomes `BroadcastStatus.cancelled` with a `cancelledAt` timestamp, leaves `watchPending()` and stays in `listAll()`.
An unresolved relay set and a push queued by `rebroadcast` are dropped.
It returns `null` if no such record exists.

 - An entry that is already delivered, failed or superseded keeps its status. Only a queued `rebroadcast` push is dropped.
 - An attempt already in flight still completes and records its acks.
 - Relays that acked keep the event. To remove it from them, publish a NIP-09 `kind:5` deletion.
 - `broadcast` with the same event and `account` reopens the entry. `rebroadcast` forces one push and the entry stays cancelled.

### Terminal failures

NIP-01 requires failed `OK` messages to start with a machine-readable prefix followed by `:`.
When a relay refuses the event with one of these prefixes, the queue records the message in `QueuedBroadcast.terminalErrors` and stops retrying that relay for the event:

 - `blocked`
 - `invalid`
 - `mute`
 - `pow`
 - `restricted`

An event longer than the relay reads (`RelayFailureKind.messageTooLong`) and a relay the `RelayManager` blocks (`RelayFailureKind.blocked`) are terminal too.
If every target relay is either acked or terminally refused, and at least one is refused, the entry becomes `BroadcastStatus.failed` and leaves `watchPending()`.

Other refusals, such as `rate-limited:`, `auth-required:` or `error:` (NIP-01's example is `error: could not connect to the database`), unknown prefixes and messages without a colon, stay retryable, and so do the failures of an identity (`cannotSign`, `authenticationFailed`, etc.) and the exceptions a `BroadcastFn` throws.
A relay that could not be reached, dropped the connection or timed out stays retryable until it has been unreachable for `maxInaccessibleAttemptsPerRelay` (12) consecutive online attempts.

`rebroadcast` can still force another push.
If a terminally refused relay later accepts the event, its terminal error is cleared and the entry can become `delivered`.

### What the queue does not do

 - **It never signs.** Sign the event before queuing it.
 - **It never auto-deletes records.** Even after full delivery, an entry stays in the database until `clearLocalAccountData`, `clearAllLocalData`, or sembast itself removes it.
 - **It applies no max-attempts limit.** Retryable failures continue with exponential backoff until they ack, are cancelled, are terminally refused, or hit the dead relay cutoff.

## Tuning

```dart
BroadcastQueue.withDostr(
  relayManager,
  db: db,
  publishTimeout: defaultPublishTimeout,       // how long each attempt waits for the relays, NIP-42 aside
  storeName: 'broadcasts',                     // sembast store name
  tickInterval: const Duration(seconds: 30),   // periodic retry scan
  initialBackoff: const Duration(seconds: 5),  // backoff floor
  maxBackoff: const Duration(minutes: 30),     // backoff ceiling
  maxInaccessibleAttemptsPerRelay: 12,         // stops dead relays while online
  maxConcurrentPublishes: 10,                  // publishes at once, the others wait their turn
);
```

## Architecture in one diagram

```
caller.broadcast(event, relaySet)
        │
        ▼
  sembast write ──── durable, returns to caller here
        │
        ▼
  resolve pendingRelaySet (once)         ────►  retry with backoff while unavailable
        │
        ▼
  wait for a publish slot                ────►  maxConcurrentPublishes, oldest entry first
        │
        ▼
  RelayPublishes.publish(event, relays: remaining).done
        │
        ▼
  accepted into ackedRelays              ────►  delivered when ⊇ relays
  terminal refusal into terminalErrors   ────►  failed when all remaining are terminal
  unreachable while online               ────►  terminal after 12 online attempts
  retryable error into lastErrors              (otherwise schedule backoff)
```

A `Timer.periodic` scans for due entries every `tickInterval` and replays whatever is overdue, oldest entry first.
`retryNow()` runs the same scan immediately.

## Testing your integration

`BroadcastQueue` is unit-testable without relays.
Pass a `BroadcastFn` to the default constructor:

```dart
final queue = BroadcastQueue(
  broadcastFn: (event, relays, {account}) async => {
    for (final relay in relays) relay: const RelayPublishOutcome.accepted(),
  },
  db: await newDatabaseFactoryMemory().openDatabase('test.db'),
);
```

The package's own test suite uses exactly this approach, see [test/support/fake_broadcaster.dart](test/support/fake_broadcaster.dart).

## Coming from `broadcast_queue_shim_for_ndk`

`OfflineBroadcast` is `BroadcastQueue`, and `OfflineBroadcast.withNdk(ndk, ...)` is `BroadcastQueue.withDostr(relayManager, ...)`.
The rest of the API is the same, with these changes:

 - `pubkey` is `account`, on `broadcast`, `get`, `watch`, `rebroadcast`, `cancel`, `clearLocalAccountData`, `QueuedBroadcast` and `QueuedBroadcast.keyFor`. Stored records keep their `pubkey` field.
 - `BroadcastFn` takes the event, the relays as `RelayUrl`s and the `account` the event was queued under, and returns the `RelayPublishOutcome` of each relay. `perAttemptTimeout` is `publishTimeout` on `withDostr`: a `BroadcastFn` bounds its own attempts.
 - `withNdk` built the relay list lookups itself. Pass `relayListFn`, built with `fetcherUrlListFn` of `dostr_fetchers`: `relayListDiscoveryRelays` and `relayListQueryTimeout` are the `relays` and `timeout` of its fetchers.
 - `UrlSet` comes from `dostr_url_set`, which this package does not re-export.
 - `QueuedBroadcast.relays`, `ackedRelays`, `forcedRelays` and the keys of `lastErrors`, `terminalErrors` and `inaccessibleAttempts` are `RelayUrl`s.
 - `broadcast` throws on an unsigned event, where NDK signed it.
 - Errors read `refused`, `no response`, `timed out` or the `RelayFailure` of the relay, such as `unreachable: <reason>`, where they read `rejected` and `no response (timeout or relay unreachable)`.
 - An event too long for a relay, a `mute:` refusal and a relay the `RelayManager` blocks are refused for good. An `error:` refusal is retried.
 - An attempt made offline no longer grows the backoff, and one in which a relay answered counts as online. The backoff starts over when `broadcast` queues the entry again or `rebroadcast` gives it a new relay.
 - A newer version of a replaceable or addressable event supersedes an older one only once newer versions head to all its relays.
 - At most `maxConcurrentPublishes` entries publish at once, oldest first. Without `onlineSignal`, `withDostr` no longer pauses the periodic retries, see [Connectivity](#connectivity).
 - `dispose` abandons an attempt still waiting on the relays, where it waited for it.

A queue stored by the shim loads unchanged: pass the same database and `storeName`.
An event the shim stored unsigned, counting on NDK to sign it, is never sent: a signed copy has the same id, so remove the record from the store before queuing the event again, signed.
