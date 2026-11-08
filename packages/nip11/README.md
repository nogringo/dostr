# ndk_nip11

[NIP-11](https://github.com/nostr-protocol/nips/blob/master/11.md) relay information for [NDK](https://pub.dev/packages/ndk): fetch the document a relay serves about itself (name, software, supported NIPs, limitations, fees). It depends on neither `ndk` nor `ndk_core`.

## With NDK

`ndk` depends on this package and re-exports it. `ndk.connectivity` fetches the document once per relay and caches it for an hour, and asks a relay that could not be reached again after a minute. It returns null when the relay serves no document or could not be reached:

```dart
import 'package:ndk/ndk.dart';

final info = await ndk.connectivity.getRelayInfo('wss://relay.example.com');
print('search? ${info?.supportsNip('50') ?? false}');
```

## Standalone

```yaml
dependencies:
  ndk_nip11: ^0.1.0
  ndk_http: ^0.1.0
  http: ^1.6.0
```

```dart
import 'package:http/http.dart' as http;
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nip11/ndk_nip11.dart';

final repo = HttpRelayInfoRepo(NdkHttp(http.Client()));

final info = await repo.getRelayInfo('wss://relay.example.com');
print(info?.limitation?.maxSubscriptions);
```

`getRelayInfo` fetches the document over HTTP(S) on the relay's own url, on every call, with no cache. It returns null when the relay answers without one: an error status, a body that is not a JSON object, or one past `maxBytes` (1 MiB by default). It throws when the relay could not be reached, since asking again later may work: a timeout, a network failure, a 408, a 429 or a 5xx. A url that is not ws, wss, http or https throws an `ArgumentError`.

To fetch it once per relay, wrap the repo in `CachedRelayInfoRepo`. It also remembers a relay that answered without a document, and serves each answer for `maxAge`, or as long as it lives without one. Concurrent calls share the request. A fetch that throws is asked again on the next call, or once `failureMaxAge` passes, so a relay that is down or rate limits is not asked on every call. `evict(url)` and `clear()` forget what it holds. It keys the cache on the url as given, so normalize urls first:

```dart
final cached = CachedRelayInfoRepo(
  repo,
  maxAge: const Duration(hours: 1),
  failureMaxAge: const Duration(minutes: 1),
);
```

`RelayInfo.toJson` gives the document back under its NIP-11 names, so it can be persisted and read again with `RelayInfo.fromJson`. The fields the package does not read, such as `retention` or `relay_countries`, stay in `extra` and come back in `toJson`.

The constructors build a document to fake a relay in a test, and two documents with the same fields are equal:

```dart
final info = RelayInfo(
  nips: [1, 50],
  limitation: RelayLimitation(maxSubscriptions: 200),
);
```

More in [example/](example/) and the [connectivity docs](https://dart-nostr.com/usecases/connectivity/).

## Coming from `ndk`

`RelayInfo`, `RelayLimitation`, `RelayFees`, `RelayFee` and `RelayInfoRepo` keep their names, and `package:ndk/ndk.dart` now exports them all. `RelayInfoHttpRepoImpl(httpDS: http)` is now `HttpRelayInfoRepo(http)`. The deep imports under `package:ndk/` (`domain_layer/entities/relay_info.dart`, `domain_layer/repositories/relay_info_repo.dart` and `data_layer/repositories/relay_info_http_impl.dart`) are now `package:ndk_nip11/ndk_nip11.dart`. `Connectivy` stays in `ndk`, and its cache is now `CachedRelayInfoRepo`.
