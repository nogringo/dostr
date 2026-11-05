import 'dart:async';

import 'package:ndk_core/shared/logger/logger.dart';
import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import '../../repositories/cache_manager.dart';

/// Cache-first helper for request resolution.
///
/// This usecase is intentionally small: it asks the cache for currently visible
/// events matching unresolved filters and forwards them into the request
/// response stream before or alongside network results.
class CacheRead {
  final CacheManager cacheManager;

  CacheRead(this.cacheManager);

  /// Finds the visible events the cache holds for each filter with ids or
  /// authors, every other field of the filter applying too, forwards them to
  /// [outController] and closes it. A filter with neither is left to the
  /// network.
  ///
  /// Returns the filters the network still has to answer: an id found here is
  /// removed from its filter, and a filter left without ids is dropped.
  ///
  /// `loadEvents()` already applies visibility rules, so callers do not need to
  /// re-check replacement, expiration, or deletion here.
  Future<List<Filter>> resolveUnresolvedFilters({
    required List<Filter> filters,
    required StreamController<Nip01Event> outController,
  }) async {
    final unresolved = List.of(filters);
    for (final filter in filters.toSet()) {
      final ids = filter.ids;
      if (ids == null && filter.authors == null) continue;

      final cached = await cacheManager.loadEvents(
        ids: ids,
        pubKeys: filter.authors,
        kinds: filter.kinds,
        tags: filter.tags,
        since: filter.since,
        until: filter.until,
        search: filter.search,
        limit: filter.limit,
      );

      if (ids != null) {
        final found = {for (final event in cached) event.id};
        ids.removeWhere(found.contains);
        if (ids.isEmpty) unresolved.remove(filter);
      }

      for (final event in cached) {
        Logger.log.t(() => "found event in cache $event ");
        outController.add(event);
      }
    }

    /// close stream even if nothing was found
    outController.close();
    return unresolved;
  }
}
