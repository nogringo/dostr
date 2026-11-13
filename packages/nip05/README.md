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

final nip05 = Nip05Usecase(
  cache: myCache,
  nip05Repository: Nip05HttpRepositoryImpl(client: http.Client()),
);

switch (await nip05.resolve('bob@example.com')) {
  case Nip05Found(:final data):
    print('${data.pubKey} ${data.relays}');
  case Nip05NotFound():
    print('no such user');
  case Nip05ResolveError(:final cause):
    print('try again later: $cause');
}
```

`cache` is a `Nip05Cache`, keyed by the canonical identifier (`Nip05.canonicalIdentifier`). A found identifier is kept for `NIP_05_VALID_DURATION` (24 hours), a missing one for `NIP_05_NOT_FOUND_DURATION` (1 hour). Concurrent calls for the same identifier share one request. `check` resolves the identifier and tells whether it points to the given pubkey.

More in [example/](example/) and the [domain verification docs](https://nogringo.github.io/dostr/usecases/domain-verification/).

## Coming from `ndk`

The classes keep their names. The deep imports under `package:ndk/` (`config/nip_05_defaults.dart`, `data_layer/repositories/nip_05_http_impl.dart`, `domain_layer/entities/nip_05.dart`, `domain_layer/entities/nip_05_resolve_result.dart`, `domain_layer/repositories/nip_05_repo.dart` and `domain_layer/usecases/nip05/nip_05.dart`) are now `package:dostr_nip05/dostr_nip05.dart`. `Nip05Usecase` takes `cache` instead of `database`, and `Nip05Model` is gone.
