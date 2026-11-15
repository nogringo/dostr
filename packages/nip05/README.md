# dostr_nip05

[NIP-05](https://github.com/nostr-protocol/nips/blob/master/05.md) identifiers for Nostr: resolve a `name@domain` address to a pubkey and its relays through `/.well-known/nostr.json`, and verify that it belongs to a pubkey.

## Standalone

```yaml
dependencies:
  dostr_nip05: ^0.1.0
  http: ^1.6.0
```

```dart
import 'package:http/http.dart' as http;
import 'package:dostr_nip05/dostr_nip05.dart';

final nip05 = Nip05Resolver(
  nip05Repository: HttpNip05Repository(client: http.Client()),
);

switch (await nip05.resolve('bob@example.com')) {
  case Nip05Found(:final data):
    print('${data.pubkey} ${data.relays}');
  case Nip05NotFound():
    print('no such user');
  case Nip05ResolveError(:final cause):
    print('try again later: $cause');
}
```

`resolve` tells a missing address (`Nip05NotFound`) apart from a server that could not be reached (`Nip05ResolveError`).
`relays` lists the relays the domain gives for the pubkey, if any.

To check an address against a pubkey you already have:

```dart
final result = await nip05.check(
  nip05: 'username@domain.example',
  pubkey: '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
);
print('valid? ${result.valid}, relays: ${result.relays}');
```

Without a `cache`, the resolver keeps what it resolved in memory.
To keep it across restarts, pass a `Nip05Cache` on your storage, keyed by the canonical identifier (`Nip05.canonicalIdentifier`).
A found identifier is kept for `nip05ValidDuration` (24 hours), a missing one for `nip05NotFoundDuration` (1 hour).
A request gives up after `nip05RequestTimeout` (5 seconds).
Concurrent calls for the same identifier share one request.

More in [example/](example/).

## Coming from `ndk`

`Nip05Usecase` is now `Nip05Resolver` and `Nip05HttpRepositoryImpl` is now `HttpNip05Repository`.
The other classes keep their names.
The deep imports under `package:ndk/` (`config/nip_05_defaults.dart`, `data_layer/repositories/nip_05_http_impl.dart`, `domain_layer/entities/nip_05.dart`, `domain_layer/entities/nip_05_resolve_result.dart`, `domain_layer/repositories/nip_05_repo.dart` and `domain_layer/usecases/nip05/nip_05.dart`) are now `package:dostr_nip05/dostr_nip05.dart`.
`Nip05Resolver` takes `cache` instead of `database`, and `Nip05Model` is gone.
