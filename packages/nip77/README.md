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

## Coming from `ndk` or `dostr_core`

`package:dostr_core/shared/nips/nip77/negentropy.dart` and the `Nip77`,
`Nip77Response` and `Nip77Result` classes are now all in
`package:dostr_nip77/dostr_nip77.dart`. `Nip77` takes the `RelayManager` and
two cache reads instead of `GlobalState` and a `CacheManager`, and no longer has
`processNegMsg`, `processNegErr` or `processNegClosed`: it registers itself on
the `RelayManager`.
