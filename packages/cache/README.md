# ndk_cache

The cache of [NDK](https://pub.dev/packages/ndk): the `CacheManager` contract that cache backends implement, the in-memory `MemCacheManager`, and the records they store. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package and re-exports it. Pass a `CacheManager` as `NdkConfig.cache`:

```dart
import 'package:ndk/ndk.dart';

final ndk = Ndk(
  NdkConfig(cache: MemCacheManager(), eventVerifier: Bip340EventVerifier()),
);
```

`MemCacheManager` loses everything on restart. For a cache that survives it, use a persistent backend: [`ndk_sembast`](https://pub.dev/packages/ndk_sembast), [`ndk_drift`](https://pub.dev/packages/ndk_drift), [`ndk_sqlite3`](https://pub.dev/packages/ndk_sqlite3) or [`ndk_objectbox`](https://pub.dev/packages/ndk_objectbox).

## Standalone

```yaml
dependencies:
  ndk_cache: ^0.1.0
```

```dart
import 'package:ndk_cache/ndk_cache.dart';

final cache = MemCacheManager();
await cache.saveEvents([oldProfile, newProfile]);

// only the newest kind 0 of the author
final visible = await cache.loadEvents(kinds: [0], pubKeys: [pubkey]);

// the older one is still stored
final history = await cache.loadHiddenEvents(
  kinds: [0],
  pubKeys: [pubkey],
  reasons: {HiddenEventReason.superseded},
);
```

`loadEvents` returns visible events only: the winner of each replaceable or addressable conflict, without expired events (NIP-40) and events their author deleted (NIP-09). `loadHiddenEvents` returns the others with the reason they are hidden. `evict` removes events according to an `EvictionPolicy`, and `CacheEvictionScheduler` runs it periodically.

`DecryptedEventPayloads` keeps the plaintext of encrypted events next to them, per event and viewer, so that a slow or remote signer decrypts each event once. `DecryptedPayloadsGiftWrapCache` and `DecryptedPayloadsNip51ListCache` give it to the `GiftWrap` of `ndk_nip59` and the `Lists` of `ndk_lists`.

More in [example/](example/) and the [cache behavior docs](https://dart-nostr.com/guides/cache-behavior/).

## Writing a backend

Implement `CacheManager`. It also implements the caches the NDK packages ask for (`DeliveryStore`, `Nip05Cache`, `ContactListCache`, `MetadataCache`, `Nip51ListCache` and `SearchCache`), so one backend serves them all. `EventVisibilityResolver` and `EventEvictionPlanner` hold the visibility and eviction rules, for a backend to reuse rather than reimplement. Check a backend against the shared [cache manager test suite](https://github.com/relaystr/ndk/tree/master/packages/ndk_cache_manager_test_suite).

## Coming from `ndk`

The classes keep their names, and `package:ndk/ndk.dart` and `package:ndk/entities.dart` still export the ones they exported. These deep imports under `package:ndk/` are now `package:ndk_cache/ndk_cache.dart`:

- `domain_layer/repositories/cache_manager.dart`
- `data_layer/repositories/cache_manager/mem_cache_manager.dart`
- `domain_layer/usecases/cache_eviction/cache_eviction_scheduler.dart`
- `domain_layer/entities/cache_eviction.dart`, `event_cache_records.dart`, `hidden_event.dart` and `filter_fetched_ranges.dart`
- `domain_layer/entities/user_relay_list.dart`, `nip_65.dart`, `relay_set.dart`, `pubkey_mapping.dart`, `read_write.dart` and `read_write_marker.dart`
- `shared/nips/nip01/event_visibility_resolver.dart` and `event_eviction_planner.dart`
- `shared/nips/nip09/deletion.dart` and `shared/nips/nip28/channel_metadata.dart`
- `domain_layer/usecases/decrypted_event_payloads/decrypted_event_payloads.dart`
- `data_layer/repositories/cache_manager/cache_manager_replaceable_events.dart`
