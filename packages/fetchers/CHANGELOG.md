## 0.1.0

 - Initial release.
 - `CacheManagerReplaceableEvents` lets the fetchers keep the lists they find among the events of a `CacheManager`. It moved here from `ndk_cache`, so that `ndk_cache` does not depend on `ndk_core`, and this package depends on `ndk_cache` for it. `package:ndk/data_layer/repositories/cache_manager/cache_manager_replaceable_events.dart` is now `package:ndk_fetchers/ndk_fetchers.dart`.
