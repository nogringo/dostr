import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import '../nip01/event_kind_classification.dart';
import 'package:ndk_nip19/ndk_nip19.dart';

/// NIP-19 references to an event.
extension Nip19EventReferences on Nip01Event {
  /// This event as a nevent, with its id, author and kind, and [relays] as
  /// hints, for example the ones `CacheManager.loadEventSources` returns.
  String nevent({List<String> relays = const []}) {
    return Nip19.encodeNevent(
      eventId: id,
      author: pubKey,
      kind: kind,
      relays: relays.isEmpty ? null : relays,
    );
  }

  /// This event as a naddr, with [relays] as hints, or null when its kind is
  /// not addressable or replaceable, or when it has no "d" tag.
  String? naddr({List<String> relays = const []}) {
    if (!EventKindClassification.isAddressableKind(kind) &&
        !EventKindClassification.legacyReplaceableKinds.contains(kind)) {
      return null;
    }

    final identifier = getDtag();
    if (identifier == null) {
      return null;
    }

    return Nip19.encodeNaddr(
      identifier: identifier,
      pubkey: pubKey,
      kind: kind,
      relays: relays.isEmpty ? null : relays,
    );
  }
}
