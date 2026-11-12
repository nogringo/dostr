---
icon: sync
---

# Negentropy (NIP-77)

[`dostr_nip77`](https://pub.dev/packages/dostr_nip77) runs [NIP-77](https://github.com/nostr-protocol/nips/blob/master/77.md) negentropy sync: it finds which events a relay has that you don't, and the other way around, without downloading either set. It runs on the connections of an `dostr_core` `RelayManager`, NIP-42 authentication included.

```yaml
dependencies:
  dostr_core: ^0.11.0-dev.2
  dostr_nip77: ^0.1.0
```

## Basic reconciliation

:::code source="../../packages/nip77/example/dostr_nip77_example.dart" language="dart" range="5-21" title="" :::

`Nip77` compares the relay's events with your local ones. `loadEventIds` returns the id and creation time of the local events matching a filter, and `loadEvent` reads one local event, for the ids you pass to `reconcile` as `localIds`.

`result.needIds` are on the relay and not stored locally: fetch them with [RelayReqs](/usecases/relay-reqs.md). `result.haveIds` are stored locally and not on the relay: publish them with [RelayPublishes](/usecases/relay-publishes.md). `needStream` and `haveStream` emit the ids as rounds complete.

## Timeouts

```dart
final response = nip77.reconcile(
  relayUrl: 'wss://relay.example.com',
  filter: filter,
  openTimeout: Duration(seconds: 30), // first answer to NEG-OPEN
  idleTimeout: Duration(seconds: 15), // silence between two rounds
);
```

There is no overall deadline: a large sync runs for as long as the relay keeps answering. When one of the two runs out, the future fails with `Nip77TimeoutException`, whose `openUnanswered` tells which.

## Relay authentication (NIP-42)

Some relays only reconcile with a client that authenticated, the same way they only serve a REQ to one. The `auth` parameter says which identity the reconciliation may be attributed to, as on [RelayReqs](/usecases/relay-reqs.md):

```dart
final response = nip77.reconcile(
  relayUrl: 'wss://relay.example.com',
  filter: Filter(authors: [myPubkey]),
  auth: AuthPolicy.require(account),
);
```

| policy | connection | what a relay learns |
| --- | --- | --- |
| `AuthPolicy.never()` | anonymous, always | nothing. A relay that refuses the negotiation without an identity simply does not reconcile |
| `AuthPolicy.allow(a)` | anonymous, moves to one bound to `a` once the relay refuses | who you are, but only after that relay asked |
| `AuthPolicy.require(a)` | bound to `a` from the start | who you are, as soon as it sends a challenge |

Without `auth`, a negotiation reveals no identity, unless the `RelayManager` has `accounts` and an `authHandler`: a refused negotiation then authenticates as the logged account where the handler agrees. See [NIP-42 authentication](/concepts/nip42-auth.md).

If `require` names an account that cannot sign, no connection can carry the reconciliation. Rather than fall back to the anonymous one, which is what `require` rules out, nothing is sent and `reconcile` itself throws `Nip77AuthUnavailableException`.

## Error handling

### Relay doesn't support NIP-77

A relay that refuses the negotiation with a `NEG-ERR` naming `CLOSED` fails it with `Nip77NotSupportedException`. One that ignores `NEG-OPEN` only fails with `Nip77TimeoutException` once `openTimeout` runs out (30 s by default). Pass a shorter `openTimeout` if that wait is too long:

```dart
try {
  final response = nip77.reconcile(
    relayUrl: 'wss://relay.example.com',
    filter: filter,
    openTimeout: const Duration(seconds: 10),
  );
  await response.future;
} on Nip77NotSupportedException catch (e) {
  print('Relay does not support NIP-77: ${e.message}');
  // fall back to a plain REQ
} on Nip77TimeoutException catch (e) {
  print('Reconciliation timed out: ${e.timeout}');
}
```

### Relay requires an identity you did not give it

```dart
try {
  await nip77.reconcile(
    relayUrl: 'wss://relay.example.com',
    filter: filter,
    auth: const AuthPolicy.never(),
  ).future;
} on Nip77AuthRequiredException catch (e) {
  print('Relay wants an identity: ${e.message}');
} on Nip77AuthUnavailableException catch (e) {
  print('${e.pubkey} cannot sign, nothing was sent');
}
```

## When to use

Good for:

- Syncing large event sets (long history)
- Periodic reconciliation with your relays
- Making sure a relay has all your events
- Discovering events you missed

For small queries, a plain REQ with [RelayReqs](/usecases/relay-reqs.md) is simpler.
