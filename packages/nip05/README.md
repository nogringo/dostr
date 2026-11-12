# ndk_nip05

[NIP-05](https://github.com/nostr-protocol/nips/blob/master/05.md) identifiers for [NDK](https://pub.dev/packages/ndk): resolve a `name@domain` address to a pubkey and its relays through `/.well-known/nostr.json`, and verify that it belongs to a pubkey. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes it as `ndk.nip05`, cached in the `CacheManager`:

```dart
import 'package:ndk/ndk.dart';

final result = await ndk.nip05.check(nip05: 'bob@example.com', pubkey: pubkey);
print('valid? ${result.valid}, relays: ${result.relays}');
```

## Standalone

```yaml
dependencies:
  ndk_nip05: ^0.1.0
  http: ^1.6.0
```

```dart
import 'package:http/http.dart' as http;
import 'package:ndk_nip05/ndk_nip05.dart';

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

More in [example/](example/) and the [domain verification docs](https://dart-nostr.com/usecases/domain-verification-(nip05)/).

## Coming from `ndk`

The classes keep their names, and `package:ndk/ndk.dart` now exports them all. The deep imports under `package:ndk/` (`config/nip_05_defaults.dart`, `data_layer/repositories/nip_05_http_impl.dart`, `domain_layer/entities/nip_05.dart`, `domain_layer/entities/nip_05_resolve_result.dart`, `domain_layer/repositories/nip_05_repo.dart` and `domain_layer/usecases/nip05/nip_05.dart`) are now `package:ndk_nip05/ndk_nip05.dart`. `Nip05Usecase` takes `cache` instead of `database`, and `Nip05Model` is gone.
