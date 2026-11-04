import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import 'package:ndk_core/shared/nips/nip01/event_kind_classification.dart';
import 'package:ndk_nip19/ndk_nip19.dart';

/// NIP-19 references to an event, with its sources as relay hints.
extension Nip19EventReferences on Nip01Event {
  /// This event as a nevent, with its id, author and kind.
  String get nevent {
    return Nip19.encodeNevent(
      eventId: id,
      author: pubKey,
      kind: kind,
      relays: _relayHints,
    );
  }

  /// This event as a naddr, or null when its kind is not addressable or
  /// replaceable, or when it has no "d" tag.
  String? get naddr {
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
      relays: _relayHints,
    );
  }

  // ignore: deprecated_member_use
  List<String>? get _relayHints => sources.isEmpty ? null : sources;
}
