# ndk_nip11

[NIP-11](https://github.com/nostr-protocol/nips/blob/master/11.md) relay information for [NDK](https://pub.dev/packages/ndk): fetch the document a relay serves about itself (name, software, supported NIPs, limitations, fees). It depends on neither `ndk` nor `ndk_core`.

## With NDK

`ndk` depends on this package and re-exports it. `ndk.connectivity` fetches the document once per relay and caches it, in `NdkConfig.cache` too, so a persistent backend keeps it across restarts. Past an hour, a call gets the cached document while it is fetched again in the background. It asks a relay that could not be reached again after a minute. It returns null when the relay serves no document, could not be reached, or the url is not a relay url:

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

To fetch it once per relay, wrap the repo in `CachedRelayInfoRepo`. It also remembers a relay that answered without a document. Once an answer is older than `maxAge`, a call still gets it right away while the relay is fetched again in the background, so a call waits for the network only while its relay never answered. Without `maxAge`, an answer stays until it is evicted. Concurrent calls share the request. A fetch that throws serves the last answer of that relay, and throws only for a relay that never answered. It is asked again on the next call, or once `failureMaxAge` passes, so a relay that is down or rate limits is not asked on every call. `evict(url)` and `clear()` forget what it holds. It keys the cache on the url as given, so normalize urls first:

```dart
final cached = CachedRelayInfoRepo(
  repo,
  maxAge: const Duration(hours: 1),
  failureMaxAge: const Duration(minutes: 1),
);
```

To keep the answers across restarts, give it a `RelayInfoCache`. It saves each answer as a `RelayInfoRecord`, a relay without a document included, and reads it on the first call for that relay, so a restart serves it without waiting for a request. Once `maxAge` has passed since it was fetched, it is fetched again in the background, as above. A failure is not saved, and `evict(url)` and `clear()` forget the relays in `cache` too. A read that throws fetches the relay. A call does not wait for the write, and a write that throws keeps the answer in memory only. NDK's `CacheManager` implements `RelayInfoCache`, so every NDK cache backend persists them:

```dart
final cached = CachedRelayInfoRepo(
  repo,
  cache: SqliteCacheManager(sqlite3.open('ndk.db')),
  maxAge: const Duration(hours: 1),
);
```

To write your own, store `RelayInfoRecord.toJson` under `RelayInfoRecord.url` and read it back with `RelayInfoRecord.fromJson`.

It ages answers in memory with a `Stopwatch`, which a change of the system clock does not move, and those of `cache` with the system clock, since a `Stopwatch` does not outlive the process. A test can pass `stopwatch: clock.stopwatch()` from `package:clock` and drive both with `fakeAsync`.

`RelayInfo.toJson` gives the document back under its NIP-11 names, so it can be persisted and read again with `RelayInfo.fromJson`, which takes any `Map`, such as one a Hive box gives back. The fields the package does not read, such as `retention` or `relay_countries`, stay in `extra`, read-only all the way down, and come back in `toJson`. `nips` lists the numbered NIPs first and in order, then the lettered ones, without duplicates.

The constructors build a document to fake a relay in a test, and two documents with the same fields are equal, whatever the order of their NIPs:

```dart
final info = RelayInfo(
  nips: [1, 50],
  limitation: RelayLimitation(maxSubscriptions: 200),
);
```

More in [example/](example/) and the [connectivity docs](https://dart-nostr.com/usecases/connectivity/).

## Coming from `ndk`

`RelayInfo`, `RelayLimitation`, `RelayFees`, `RelayFee` and `RelayInfoRepo` keep their names, and `package:ndk/ndk.dart` now exports them all. `RelayInfoHttpRepoImpl(httpDS: http)` is now `HttpRelayInfoRepo(http)`. The deep imports under `package:ndk/` (`domain_layer/entities/relay_info.dart`, `domain_layer/repositories/relay_info_repo.dart` and `data_layer/repositories/relay_info_http_impl.dart`) are now `package:ndk_nip11/ndk_nip11.dart`. `Connectivity` stays in `ndk`, and its cache is now `CachedRelayInfoRepo`.
