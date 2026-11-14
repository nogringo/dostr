import 'package:dostr_nip01/dostr_nip01.dart';

import 'nip19_entity.dart';

/// NIP-19 references to an event.
extension Nip19EventReferences on Nip01Event {
  /// This event as an nevent, with its id, author and kind, and [relays] as
  /// hints.
  String nevent({List<String> relays = const []}) =>
      Nevent(eventId: id, relays: relays, author: pubKey, kind: kind).encode();

  /// This event as an naddr, with [relays] as hints. A replaceable event gets
  /// an empty identifier, and an addressable one its `d` tag. Null when the
  /// kind is neither, or when an addressable event has no `d` tag.
  String? naddr({List<String> relays = const []}) {
    final identifier = EventKindClassification.isAddressableKind(kind)
        ? dTag
        : EventKindClassification.isReplaceableKind(kind)
        ? ''
        : null;
    if (identifier == null) return null;
    return Naddr(
      identifier: identifier,
      pubkey: pubKey,
      kind: kind,
      relays: relays,
    ).encode();
  }
}
