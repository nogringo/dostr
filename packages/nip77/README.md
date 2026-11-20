# dostr_nip77

[NIP-77](https://github.com/nostr-protocol/nips/blob/master/77.md) negentropy sync for Nostr: finds which events a relay has that you don't, and the other way around, without downloading either set.
It runs on the connections of a [`dostr_core`](https://pub.dev/packages/dostr_core) `RelayManager`, NIP-42 authentication included, with the [Negentropy V1](https://github.com/hoytech/negentropy/blob/master/docs/negentropy-protocol-v1.md) codec under it.

Add it next to `dostr_core`.

## Install

```yaml
dependencies:
  dostr_core: ^0.1.1
  dostr_nip77: ^0.1.0
```

## Usage

```dart
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip77/dostr_nip77.dart';

final nip77 = Nip77(
  relayManager: relays,
  loadEventIds: store.loadEventIdsWithCreatedAt,
);

final relay = RelayUrl.parse('wss://relay.example.com');
final response = nip77.reconcile(
  relayUrl: relay,
  filter: Filter(authors: [myPubkey]),
);
final result = await response.future;
// result.needIds: on the relay, not stored locally
// result.haveIds: stored locally, not on the relay
```

`loadEventIds` returns the id and creation time of the local events matching a filter.
Pass them to `reconcile` as `localIds` instead to compare another set.

`needStream` and `haveStream` emit ids as rounds complete.
Each keeps its ids until it is listened to, and closes when the reconciliation ends, whatever the outcome: `future` tells which.
Listen to `future` even when only the streams matter, since a failure nobody listens to is reported as an uncaught error.
`nip77.close(response.subscriptionId)` ends a reconciliation early: its future completes with what the rounds so far found, and `isComplete` false.
`nip77.dispose()` ends every reconciliation the same way, and stops listening to the `RelayManager`, which several `Nip77` can share.

Fetch `result.needIds` with the `RelayReqs` of `dostr_core`, and publish `result.haveIds` with its `RelayPublishes`.

Good for syncing large event sets (long history), periodic reconciliation with your relays, making sure a relay has all your events, and discovering events you missed.
For small queries, a plain REQ with `RelayReqs` is simpler.

## Timeouts

```dart
final response = nip77.reconcile(
  relayUrl: relay,
  filter: filter,
  openTimeout: Duration(seconds: 30), // first answer to NEG-OPEN
  idleTimeout: Duration(seconds: 15), // silence between two rounds
);
```

There is no overall deadline: a large sync runs for as long as the relay keeps answering.
When one of the two runs out, the future fails with `Nip77TimeoutException`, whose `openUnanswered` tells which.

## Frame size

Each NEG-MSG holds at most `frameSizeLimit` bytes before hex encoding, 60000 by default, so it stays under 128 KiB on the wire.
A larger difference takes more rounds instead of one message a relay may refuse.
Pass 0 for no limit, or at least 4096 (`NegentropyEncoder.minFrameSizeLimit`), the room the first range of a message needs.

```dart
final response = nip77.reconcile(
  relayUrl: relay,
  filter: filter,
  frameSizeLimit: 16000,
);
```

## Relay authentication (NIP-42)

Some relays only reconcile with a client that authenticated, the same way they only serve a REQ to one.
The `auth` parameter says which identity the reconciliation may be attributed to, as on `RelayReqs`:

```dart
final response = nip77.reconcile(
  relayUrl: relay,
  filter: Filter(authors: [myPubkey]),
  auth: AuthPolicy.require(account),
);
```

| policy | connection | what a relay learns |
| --- | --- | --- |
| `AuthPolicy.never()` | anonymous, always | nothing. A relay that refuses the negotiation without an identity simply does not reconcile |
| `AuthPolicy.allow(a)` | anonymous, moves to one bound to `a` once the relay refuses with `auth-required` | who you are, but only after that relay asked |
| `AuthPolicy.require(a)` | bound to `a` from the start | who you are, as soon as it sends a challenge |

Without `auth`, a negotiation reveals no identity, as with `AuthPolicy.never()`.
See the [NIP-42 authentication](https://pub.dev/packages/dostr_core#nip-42-authentication) of `dostr_core`.

If `require` names an account that cannot sign, no connection can carry the reconciliation.
Rather than fall back to the anonymous one, which is what `require` rules out, nothing is sent and `reconcile` itself throws `Nip77AuthUnavailableException`.

## Errors

Every failure of `future` is a `Nip77Exception`:

| exception | what happened |
| --- | --- |
| `Nip77NotSupportedException` | the relay answered NEG-OPEN with a NOTICE that says it does not support NIP-77 |
| `Nip77RefusedException` | the relay sent a NEG-ERR, or a CLOSED that asks for no identity |
| `Nip77TimeoutException` | the relay stopped answering, see [Timeouts](#timeouts) |
| `Nip77AuthRequiredException` | the relay asked for an identity `auth` rules out |
| `Nip77ConnectionException` | no connection to the relay opened, the `AuthHandler` refused to bind one, or, with `lost` true, the connection dropped or was closed before the end |
| `Nip77MalformedMessageException` | the relay sent a NEG-MSG the codec cannot read |

Errors thrown by `loadEventIds` come through as they are, and so does the `ArgumentError` for an entry it returns whose id is not 64 hex digits or whose creation time is out of range.
The same entry in `localIds` makes `reconcile` itself throw that `ArgumentError`, before anything is sent.

`Nip77RefusedException.code` gives the prefix of the reason.
NIP-77 suggests `blocked`, for a query too big or too old, with `maxRecords` when the relay says how many records it processes, and `closed`, for a negotiation the relay timed out.
A `restricted` refusal is one too: the relay knows the identity and does not accept it.

A relay that ignores NEG-OPEN only fails with `Nip77TimeoutException` once `openTimeout` runs out (30 s by default).
Pass a shorter `openTimeout` if that wait is too long:

```dart
try {
  final response = nip77.reconcile(
    relayUrl: relay,
    filter: filter,
    openTimeout: const Duration(seconds: 10),
  );
  await response.future;
} on Nip77NotSupportedException catch (e) {
  print('Relay does not support NIP-77: ${e.message}');
  // fall back to a plain REQ
} on Nip77RefusedException catch (e) {
  if (e.code == 'blocked') {
    // narrow the filter, or fall back to a plain REQ
  }
} on Nip77TimeoutException catch (e) {
  print('Reconciliation timed out: ${e.timeout}');
}
```

A relay that requires an identity you did not give it fails with `Nip77AuthRequiredException`.
An `auth` whose account cannot sign throws `Nip77AuthUnavailableException` from `reconcile` itself, before anything is sent:

```dart
try {
  await nip77.reconcile(
    relayUrl: relay,
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

`package:dostr_core/shared/nips/nip77/negentropy.dart` and the `Nip77`, `Nip77Response` and `Nip77Result` classes are now all in `package:dostr_nip77/dostr_nip77.dart`.
`Nip77` takes the `RelayManager` and `loadEventIds` instead of `GlobalState` and a `CacheManager`, and no longer has `processNegMsg`, `processNegErr` or `processNegClosed`: it registers itself on the `RelayManager`.
`localIds` takes each id with its creation time, and `needStream` and `haveStream` are single-subscription streams.
