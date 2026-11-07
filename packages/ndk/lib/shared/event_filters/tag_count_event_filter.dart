import 'package:ndk/domain_layer/entities/event_filter.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

import 'package:ndk_follows/ndk_follows.dart';
import 'package:ndk_cache/ndk_cache.dart';

/// filter for too many tags
/// useful for preventing hellthreads
class PTagCountEventFilter extends EventFilter {
  int maxTagCount;

  /// ..
  PTagCountEventFilter(this.maxTagCount);

  @override
  bool filter(Nip01Event event) {
    return event.kind == ContactList.kKind ||
        event.kind == Nip65.kKind ||
        event.pTags.length <= maxTagCount;
  }
}
