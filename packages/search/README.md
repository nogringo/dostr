# ndk_search

The search of [NDK](https://pub.dev/packages/ndk): find cached metadata by name or NIP-05, and events in the cache and on relays with [NIP-50](https://github.com/nostr-protocol/nips/blob/master/50.md) search. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes it as `ndk.search`, backed by the `CacheManager`:

```dart
import 'package:ndk/ndk.dart';

final profiles = await ndk.search.metadataSearch('alice');
final notes = await ndk.search.searchEvents(kinds: [1], search: 'lightning');
```

## Standalone

```yaml
dependencies:
  ndk_search: ^0.1.0
```

```dart
import 'package:ndk_search/ndk_search.dart';

final search = Search(
  query: (filter) => myRelays.query(filter),
  cache: myCache,
);

final profiles = await search.metadataSearch('alice');
final notes = await search.searchEvents(kinds: [1], search: 'lightning');
final cached = await search.searchEvents(search: 'lightning', cacheOnly: true);
```

`query` streams the events relays hold for a filter and ends once they are done. `cache` is a `SearchCache`.

`metadataSearch` only looks in the cache. `searchEvents` asks the cache and relays at once and returns both without duplicates, or the cache alone with `cacheOnly`. Relays only match `search` if they support NIP-50.

More in [example/](example/).

## Coming from `ndk`

`Search` keeps its name, and `package:ndk/ndk.dart` still exports it. The deep import `package:ndk/domain_layer/usecases/search/search.dart` is now `package:ndk_search/ndk_search.dart`. `Search` takes `query` and `cache` instead of `requests` and `cacheManager`.
