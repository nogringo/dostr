import 'package:ndk_core/shared/nips/nip01/event_kind_classification.dart';
import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import '../../repositories/cache_manager.dart';

/// A reason not to send [event] after all: the cache now holds a newer version
/// of this replaceable event, which supersedes it.
Future<String?> obsoleteReplaceableVeto(
  CacheManager cacheManager,
  Nip01Event event,
) async {
  if (!EventKindClassification.isReplaceableKind(event.kind)) {
    return null;
  }

  final dTag = event.getDtag();
  final visibleEvents = await cacheManager.loadEvents(
    pubKeys: [event.pubKey],
    kinds: [event.kind],
    tags: EventKindClassification.isAddressableKind(event.kind) && dTag != null
        ? {
            'd': [dTag],
          }
        : null,
    limit: 1,
  );

  if (visibleEvents.isEmpty || visibleEvents.single.id == event.id) {
    return null;
  }
  return 'obsolete replaceable event skipped';
}
