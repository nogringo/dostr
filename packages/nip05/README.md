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
An address that is not a NIP-05 identifier, such as one whose name holds a character outside `a-z0-9-_.` or whose domain has no dot, is a `Nip05NotFound` too, and sends no request.
Names are case-insensitive, so a `nostr.json` that lists `Bob` answers `bob@example.com` too.
`pubkey` is in lowercase hex: a `nostr.json` that gives anything else for the name, such as an npub, is a `Nip05ResolveInvalidResponse`.
So is a server that redirects, which NIP-05 forbids, or whose `nostr.json` is larger than `nip05MaxResponseBytes` (5 MiB).
In a browser, which hides the redirect, it is a `Nip05ResolveNetworkError`.
`relays` lists the relays the domain gives for the pubkey, normalized and each once, as `RelayUrl`s of [`dostr_relay_url`](https://pub.dev/packages/dostr_relay_url), which this package exports.
NIP-05 makes them optional, so a missing or mistyped list gives none rather than failing.
`fetchedAt` tells when the domain gave them, in UTC.

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

`check` throws an `ArgumentError` when `pubkey` is not in hex, such as an npub.
`Nip05Verified` and `Nip05Mismatch` give `fetchedAt` too, such as to tell how old a verification is.

## Cache

Without a `cache`, the resolver keeps what it resolved in memory, until it is older than both `validDuration` and `notFoundDuration`.
To keep it across restarts, pass a `Nip05Cache` on your storage: it saves `Nip05Record`s, keyed by their `identifier`, which `toJson` and `fromJson` turn into JSON and back.
A found identifier is kept for `validDuration`, 24 hours (`nip05ValidDuration`) by default, and a missing one for `notFoundDuration`, 1 hour (`nip05NotFoundDuration`) by default.
A domain that could not be reached gives its `Nip05ResolveNetworkError` again, without a request, to every identifier on it for `networkErrorDuration`, 1 minute (`nip05NetworkErrorDuration`) by default, so a feed does not wait on a dead domain for each of its authors.
A `Nip05ResolveInvalidResponse` is given again, without a request, to its identifier for `invalidResponseDuration`, 10 minutes (`nip05InvalidResponseDuration`) by default, so a `nostr.json` that gives an npub is not asked again on every call.
`refresh: true` asks the domain whatever was remembered, such as when the user just fixed their `nostr.json`:

```dart
final nip05 = Nip05Resolver(notFoundDuration: const Duration(minutes: 10));
final result = await nip05.resolve('bob@example.com', refresh: true);
```

An error of the cache is ignored: when it cannot read, the call asks the domain, and when it cannot save, the call still gives what the domain answered.
Concurrent calls for the same identifier share one request.
At most `maxConcurrentRequests` requests run at once, 16 (`nip05MaxConcurrentRequests`) by default, and the others wait their turn, so a feed of 500 authors does not open 500 connections at once.
One that waits on a domain found unreachable meanwhile gives that `Nip05ResolveNetworkError` without a request.

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
A request gives up after `nip05RequestTimeout` (5 seconds), counted from when it is sent, which gives a `Nip05ResolveNetworkError`.

## HTTP client

`Nip05Resolver` talks to the domains through an `http.Client` of its own, or through the `httpClient` you give it, such as a `cupertino_http` or `cronet_http` client in a Flutter app.
The timeout and an `abortTrigger` end the call even through a client that cannot abort a request, such as `cupertino_http` before 2.3.0 or `cronet_http` before 1.5.0, whose request then goes on in the background.
`nip05.close()` ends what is in flight and closes the client it made, after which `resolve` and `check` throw a `StateError`.
A client you gave it stays open, since it is yours to close.
`nip05Repository` replaces the HTTP layer, such as an `HttpNip05Repository` with another `timeout` or `maxResponseBytes`, and cannot be given with `httpClient`.

More in [example/](example/).

## Coming from `ndk`

`Nip05Usecase` is now `Nip05Resolver` and `Nip05HttpRepositoryImpl` is now `HttpNip05Repository`.
The other classes keep their names.
The deep imports under `package:ndk/` (`config/nip_05_defaults.dart`, `data_layer/repositories/nip_05_http_impl.dart`, `domain_layer/entities/nip_05.dart`, `domain_layer/entities/nip_05_resolve_result.dart`, `domain_layer/repositories/nip_05_repo.dart` and `domain_layer/usecases/nip05/nip_05.dart`) are now `package:dostr_nip05/dostr_nip05.dart`.
`Nip05Resolver` takes `cache` instead of `database`, which saves `Nip05Record`s, and `Nip05Model` is gone.
`check` returns a `Nip05CheckResult` to switch on, rather than a `Nip05` whose `valid` was false whether the address pointed elsewhere, did not exist or could not be reached.
`Nip05` holds only what the domain gives: `valid` and `copyWith` are gone, `networkFetchTime` is now the `fetchedAt` of `Nip05Found`, `Nip05Verified` and `Nip05Mismatch`, `pubKey` is now `pubkey` and never null, and `relays` are `RelayUrl`s.
A redirect is no longer followed, since NIP-05 forbids it.
