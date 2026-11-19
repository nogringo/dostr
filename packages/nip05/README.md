# dostr_nip05

[NIP-05](https://github.com/nostr-protocol/nips/blob/master/05.md) identifiers for Nostr: resolve a `name@domain` address to a pubkey and its relays through `/.well-known/nostr.json`, and verify that it belongs to a pubkey.

## Standalone

```yaml
dependencies:
  dostr_nip05: ^0.1.0
```

```dart
import 'package:dostr_nip05/dostr_nip05.dart';

final nip05 = Nip05Resolver();

switch (await nip05.resolve('bob@example.com')) {
  case Nip05Found(:final data):
    print('${data.pubkey} ${data.relays}');
  case Nip05NotFound():
    print('no such user');
  case Nip05ResolveError(:final cause):
    print('try again later: $cause');
}
```

`resolve` tells a missing address (`Nip05NotFound`) apart from a server that could not be reached or gave a broken `nostr.json` (`Nip05ResolveError`).
An address that is not a NIP-05 identifier, such as one whose name holds a character outside `a-z0-9-_.`, is a `Nip05NotFound` too, and sends no request.
`pubkey` is in lowercase hex: a `nostr.json` that gives anything else for the name, such as an npub, is a `Nip05ResolveInvalidResponse`.
`relays` lists the relays the domain gives for the pubkey, normalized and each once, as `RelayUrl`s of [`dostr_relay_url`](https://pub.dev/packages/dostr_relay_url), which this package exports.
NIP-05 makes them optional, so a missing or mistyped list gives none rather than failing.

To check an address against a pubkey you already have:

```dart
switch (await nip05.check(nip05: 'bob@example.com', pubkey: pubkey)) {
  case Nip05Verified():
    print('verified');
  case Nip05Mismatch(:final data):
    print('bob@example.com belongs to ${data.pubkey}');
  case Nip05NotFound():
    print('no such user');
  case Nip05ResolveError():
    print('could not check, try again later');
}
```

## Cache

Without a `cache`, the resolver keeps what it resolved in memory.
To keep it across restarts, pass a `Nip05Cache` on your storage: it saves `Nip05Record`s, keyed by their `identifier`, which `toJson` and `fromJson` turn into JSON and back.
A found identifier is kept for `nip05ValidDuration` (24 hours), a missing one for `nip05NotFoundDuration` (1 hour), and an error not at all.
An error of the cache is not caught: `resolve` and `check` throw it.
Concurrent calls for the same identifier share one request.

## Cancelling

`resolve` and `check` take an `abortTrigger`, as the requests of `package:http` do.
Once it completes, with a value or an error, that call ends with a `RequestAbortedException`, while the others go on:

```dart
final cancel = Completer<void>();
final result = nip05.resolve('bob@example.com', abortTrigger: cancel.future);
cancel.complete(); // the screen showing it closed
```

A request shared by several calls is aborted once none of them waits on it any more.
`nip05.abortPending()` ends every call in flight the same way, and the resolver stays usable.
A request gives up after `nip05RequestTimeout` (5 seconds), which gives a `Nip05ResolveNetworkError`.

## HTTP client

`Nip05Resolver` talks to the domains through an `http.Client` of its own, or through the `httpClient` you give it, such as a `cupertino_http` or `cronet_http` client in a Flutter app.
`nip05.close()` ends what is in flight and closes the client it made.
A client you gave it stays open, since it is yours to close.
`nip05Repository` replaces the HTTP layer, such as an `HttpNip05Repository` with another `timeout`, and cannot be given with `httpClient`.

More in [example/](example/).

## Coming from `ndk`

`Nip05Usecase` is now `Nip05Resolver` and `Nip05HttpRepositoryImpl` is now `HttpNip05Repository`.
The other classes keep their names.
The deep imports under `package:ndk/` (`config/nip_05_defaults.dart`, `data_layer/repositories/nip_05_http_impl.dart`, `domain_layer/entities/nip_05.dart`, `domain_layer/entities/nip_05_resolve_result.dart`, `domain_layer/repositories/nip_05_repo.dart` and `domain_layer/usecases/nip05/nip_05.dart`) are now `package:dostr_nip05/dostr_nip05.dart`.
`Nip05Resolver` takes `cache` instead of `database`, which saves `Nip05Record`s, and `Nip05Model` is gone.
`check` returns a `Nip05CheckResult` to switch on, rather than a `Nip05` whose `valid` was false whether the address pointed elsewhere, did not exist or could not be reached.
`Nip05` holds only what the domain gives: `valid`, `networkFetchTime` and `copyWith` are gone, `pubKey` is now `pubkey` and never null, and `relays` are `RelayUrl`s.
