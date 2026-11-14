# dostr_nip77

[NIP-77](https://github.com/nostr-protocol/nips/blob/master/77.md) negentropy
sync for Nostr: finds which events a relay has that you don't, and the other way
around, without downloading either set. It runs on the connections of an
[`dostr_core`](https://pub.dev/packages/dostr_core) `RelayManager`, NIP-42
authentication included, with the
[Negentropy V1](https://github.com/hoytech/negentropy/blob/master/docs/negentropy-protocol-v1.md)
codec under it.

Add it next to `dostr_core`.

## Install

```yaml
dependencies:
  dostr_core: ^0.11.0-dev.2
  dostr_nip77: ^0.1.0
```

## Usage

```dart
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip77/dostr_nip77.dart';

final nip77 = Nip77(
  relayManager: relays,
  loadEventIds: store.loadEventIdsWithCreatedAt,
  loadEvent: store.loadEvent,
);

final response = nip77.reconcile(
  relayUrl: 'wss://relay.example.com',
  filter: Filter(authors: [myPubkey]),
);
final result = await response.future;
// result.needIds: on the relay, not stored locally
// result.haveIds: stored locally, not on the relay
```

`loadEventIds` returns the id and creation time of the local events matching a
filter. `loadEvent` reads one local event, for the ids you pass to `reconcile`
as `localIds`. `needStream` and `haveStream` emit ids as rounds complete.

Fetch `result.needIds` with the `RelayReqs` of `dostr_core`, and publish
`result.haveIds` with its `RelayPublishes`.

Good for syncing large event sets (long history), periodic reconciliation with
your relays, making sure a relay has all your events, and discovering events you
missed. For small queries, a plain REQ with `RelayReqs` is simpler.

## Timeouts

```dart
final response = nip77.reconcile(
  relayUrl: 'wss://relay.example.com',
  filter: filter,
  openTimeout: Duration(seconds: 30), // first answer to NEG-OPEN
  idleTimeout: Duration(seconds: 15), // silence between two rounds
);
```

There is no overall deadline: a large sync runs for as long as the relay keeps
answering. When one of the two runs out, the future fails with
`Nip77TimeoutException`, whose `openUnanswered` tells which.

## Relay authentication (NIP-42)

Some relays only reconcile with a client that authenticated, the same way they
only serve a REQ to one. The `auth` parameter says which identity the
reconciliation may be attributed to, as on `RelayReqs`:

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

Without `auth`, a negotiation reveals no identity, unless the `RelayManager` has
`accounts` and an `authHandler`: a refused negotiation then authenticates as the
logged account where the handler agrees. See the
[NIP-42 authentication](https://pub.dev/packages/dostr_core#nip-42-authentication)
of `dostr_core`.

If `require` names an account that cannot sign, no connection can carry the
reconciliation. Rather than fall back to the anonymous one, which is what
`require` rules out, nothing is sent and `reconcile` itself throws
`Nip77AuthUnavailableException`.

## Errors

A relay that refuses the negotiation with a `NEG-ERR` naming `CLOSED` fails it
with `Nip77NotSupportedException`. One that ignores `NEG-OPEN` only fails with
`Nip77TimeoutException` once `openTimeout` runs out (30 s by default). Pass a
shorter `openTimeout` if that wait is too long:

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

A relay that requires an identity you did not give it fails with
`Nip77AuthRequiredException`:

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

## Coming from `ndk` or `dostr_core`

`package:dostr_core/shared/nips/nip77/negentropy.dart` and the `Nip77`,
`Nip77Response` and `Nip77Result` classes are now all in
`package:dostr_nip77/dostr_nip77.dart`. `Nip77` takes the `RelayManager` and
two cache reads instead of `GlobalState` and a `CacheManager`, and no longer has
`processNegMsg`, `processNegErr` or `processNegClosed`: it registers itself on
the `RelayManager`.
