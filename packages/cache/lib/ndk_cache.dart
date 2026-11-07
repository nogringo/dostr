/// The cache of NDK: the [CacheManager] contract that cache backends
/// implement, the in-memory [MemCacheManager] and the records they store.
///
/// ```dart
/// final cache = MemCacheManager();
/// await cache.saveEvent(event);
/// final visible = await cache.loadEvents(kinds: [0], pubKeys: [pubkey]);
/// final history = await cache.loadHiddenEvents(
///   kinds: [0],
///   pubKeys: [pubkey],
///   reasons: {HiddenEventReason.superseded},
/// );
/// ```
library;

export 'src/cache_eviction.dart';
export 'src/cache_eviction_scheduler.dart';
export 'src/cache_manager.dart';
export 'src/channel_metadata.dart';
export 'src/deletion.dart';
export 'src/event_cache_records.dart';
export 'src/event_eviction_planner.dart';
export 'src/event_visibility_resolver.dart';
export 'src/filter_fetched_ranges.dart';
export 'src/hidden_event.dart';
export 'src/mem_cache_manager.dart';
export 'src/nip_65.dart';
export 'src/pubkey_mapping.dart';
export 'src/read_write.dart';
export 'src/read_write_marker.dart';
export 'src/relay_set.dart';
export 'src/user_relay_list.dart';
