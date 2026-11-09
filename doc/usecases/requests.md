---
icon: arrow-down-left
---

[!badge variant="primary" text="low level"]

!!!warning Relay Misbehavior
Relays can misbehave and return events that do not match your query filters.
!!!

## Usage Example

:::code source="../../packages/ndk/example/basic_test.dart" language="dart" range="23-44" :::

## When to use

Requests should be used when no other use case fits your needs. \
There is `.query` and `.subscription` representing the nostr equivalent, `.subscription` should only be used when absolutely necessary. Many relays limit the amount of simultaneous subscriptions.

`Requests` lives in the `ndk_requests` package, with the JIT and relay sets engines, which `ndk` depends on and re-exports. It does not depend on `ndk`: build `Requests` with a cache, a `RelayManager` and an engine, see its [README](https://pub.dev/packages/ndk_requests).

## Relay Authentication (NIP-42)

Some relays only serve a request to a client that authenticated. A connection
carries at most one identity, chosen when it is opened and immutable for its
whole lifetime, so choosing an identity is really choosing a connection. The
`auth` parameter says which one a request may use:

```dart
final account = Account(
  pubkey: myPubkey,
  type: AccountType.privateKey,
  signer: Bip340EventSigner(privateKey: myPrivkey, publicKey: myPubkey),
  // Use NdkEventSigner from ndk_flutter for automatic web/native selection
);

// the account does not have to be one of ndk.accounts: handing it over is
// enough, and it can differ from the one that is logged in
final response = ndk.requests.query(
  filter: Filter(kinds: [1059], authors: [myPubkey]),
  auth: AuthPolicy.allow(account),
);
```

### The three policies

| policy | connection | what a relay learns |
| --- | --- | --- |
| `AuthPolicy.never()` | anonymous, always | nothing. A relay that refuses the request without an identity simply does not serve it, and the request returns what the other relays gave |
| `AuthPolicy.allow(a)` | anonymous, moves to one bound to `a` once a relay refuses | who you are, but only after that relay asked |
| `AuthPolicy.require(a)` | bound to `a` from the start | who you are, as soon as it sends a challenge |

Report an event without ever being attributable for it:

```dart
ndk.requests.query(
  filter: Filter(kinds: [1], ids: [suspiciousEventId]),
  auth: const AuthPolicy.never(),
);
```

Read your own encrypted data, which no relay should serve to anyone else:

```dart
ndk.requests.query(
  filter: Filter(kinds: [1059], authors: [myPubkey]),
  auth: AuthPolicy.require(account),
);
```

### What `require` guarantees, exactly

The request is never written to a connection other than one reserved for that
account. It does not mean the relay knows who asked: NIP-42 has no way to
authenticate unprompted, so a relay that never sends a challenge never learns
the identity. It also does not mean no anonymous socket to that relay exists.
Other requests may have opened one, and the JIT engine, when it picks relays
from the outbox model, discovers them on anonymous connections before routing
the request onto the bound one, which costs a second socket to the same relay. Explicit relays go straight to the bound connection.

If the account cannot sign, no connection can carry the request at all. Rather
than fall back to the anonymous one, which is what `require` rules out, it is
sent to no relay and completes right away with whatever the local cache held.
Its timeout never fires: nothing timed out, the request was impossible from the
start.

### One request, one identity

A request authenticates as at most one account. To read data belonging to
several identities, issue one request per identity: each gets its own
connection, and a relay never sees two of your identities on the same socket.

### The default

Without `auth`, a request reveals no identity. With an [`AuthHandler`](/concepts/nip42-auth.md#authhandler), a request
that meets `auth-required` authenticates as the logged-in account where the
handler agrees.

### Migrating from `authenticateAs`

`authenticateAs` was removed. Replace it with `auth`:

| `authenticateAs` | replace with |
| --- | --- |
| `[a]` | `auth: AuthPolicy.allow(a)` |
| `[a, b]` | `auth: AuthPolicy.allow(a)`, and one more request per other identity |
| a list where no account can sign | `auth: const AuthPolicy.never()` |

A list never authenticated as more than one identity: only the first account
that could sign was ever used. If you passed `[a, b]` expecting both to be
covered, issue one request per identity, each with its own `auth`.

`allow` also differs in one way. `authenticateAs` opened an authenticated
connection before any relay asked for one, which revealed the identity even to
relays that would have served the request anonymously. `allow` waits for the
refusal.

## Event sources

When a request writes to the cache (`cacheWrite`, on by default), NDK records
every relay that sent each event. This provenance answers where an event was
observed, and is separate from relay delivery targets.

```dart
final relays = await ndk.config.cache.loadEventSources(event.id);
final nevent = event.nevent(relays: relays);
```

A request with `cacheWrite: false` records no provenance.

For most apps, normal request and usecase APIs are enough and you do not need to access source relay data directly.

### Migrating from `Nip01Event.sources`

`Nip01Event.sources` was removed, along with `Metadata.sources` and
`ContactList.sources`. It only held the first relay that sent the event, where
`loadEventSources` returns all of them. `nevent` and `naddr` are now methods
that take the relay hints:

| before | now |
| --- | --- |
| `event.sources` | `await ndk.config.cache.loadEventSources(event.id)` |
| `event.nevent` | `event.nevent(relays: relays)` |
| `event.naddr` | `event.naddr(relays: relays)` |

The cache managers move the relays they stored in each event into the
provenance when they open an existing database (for sembast, when it is opened
through `SembastCacheManager.create`).
