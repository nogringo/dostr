# ndk_requests

Queries and subscriptions for [NDK](https://pub.dev/packages/ndk), routed to the outbox relays of their authors (NIP-65), with cache reads, deduplication of identical requests, pagination and fetched ranges. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes `Requests` as `ndk.requests`:

```dart
import 'package:ndk/ndk.dart';

final ndk = Ndk.defaultConfig();
final notes = await ndk.requests
    .query(filter: Filter(kinds: [1], authors: [pubkey], limit: 10))
    .future;
```

## Standalone

```yaml
dependencies:
  ndk_requests: ^0.1.0
  ndk_cache: ^0.1.0
  ndk_core: ^0.11.0-dev.2
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_requests/ndk_requests.dart';

const bootstrapRelays = ['wss://purplepag.es', 'wss://relay.primal.net'];
final cache = MemCacheManager();
final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);

final requests = Requests(
  cacheRead: CacheRead(cache),
  cacheManager: cache,
  networkEngine: JitEngine(
    relayManagerLight: relayManager,
    cache: cache,
    ignoreRelays: const [],
    bootstrapRelays: bootstrapRelays,
  ),
  relayManager: relayManager,
  eventVerifier: Bip340EventVerifier(),
  eventOutFilters: const [],
  defaultQueryTimeout: const Duration(seconds: 10),
);

final notes = await requests
    .query(filter: Filter(kinds: [1], authors: [pubkey], limit: 10))
    .future;
```

A query ends once the relays sent what they hold, a subscription stays open until `closeSubscription`. With `cacheRead`, they answer from `cacheManager` first, and with `cacheWrite`, they save what the relays send: both are on by default for a query and off for a subscription. `explicitRelays` skips the routing.

The network engine picks the relays:

- `JitEngine` connects, request by request, to the fewest relays that cover the authors (or the `p` tags) of the filter, from the relay lists in the cache. Without one, it falls back to `bootstrapRelays`.
- `RelaySetsEngine` sends to a `RelaySet` computed beforehand, and to `bootstrapRelays` without one.

An `EventFilter` in `eventOutFilters` drops events before they reach the caller, for example `PTagCountEventFilter` against hellthreads. `FetchedRanges`, once set on `requests.fetchedRanges`, records which time ranges each relay already answered for a filter.

More in [example/](example/) and the [requests docs](https://dart-nostr.com/usecases/requests/).

## Coming from `ndk`

`Requests`, `NdkRequest`, `NdkResponse`, `EventFilter`, `PTagCountEventFilter`, `JitEngine` and `FetchedRanges` keep their names, and `package:ndk/ndk.dart` still exports them. `CacheRead`, `NetworkEngine`, `RelaySetsEngine` and the JIT relay data are here too. The deep imports under `package:ndk/` (`domain_layer/usecases/requests/`, `cache_read/`, `fetched_ranges/`, `jit_engine/`, `stream_response_cleaner/`, `engines/`, `relay_sets_engine.dart`, `domain_layer/entities/ndk_request.dart`, `request_response.dart`, `event_filter.dart`, `jit_engine_relay_connectivity_data.dart`, `shared/event_filters/tag_count_event_filter.dart` and `shared/nips/nip65/relay_ranking.dart`) are now `package:ndk_requests/ndk_requests.dart`, or internal to this package.
