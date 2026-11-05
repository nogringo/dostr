import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_fetchers/ndk_fetchers.dart' show ReplaceableEventCache;

import '../../../domain_layer/repositories/cache_manager.dart';

/// The fetchers keep the lists they find among the events of [CacheManager].
class CacheManagerReplaceableEvents implements ReplaceableEventCache {
  final CacheManager _cacheManager;

  CacheManagerReplaceableEvents(this._cacheManager);

  @override
  Future<Nip01Event?> load({
    required int kind,
    required String pubKey,
    String? dTag,
  }) async {
    final events = await _cacheManager.loadEvents(
      pubKeys: [pubKey],
      kinds: [kind],
      tags: dTag == null
          ? null
          : {
              'd': [dTag],
            },
      limit: 1,
    );
    return events.firstOrNull;
  }

  @override
  Future<void> save(Nip01Event event) => _cacheManager.saveEvent(event);
}
