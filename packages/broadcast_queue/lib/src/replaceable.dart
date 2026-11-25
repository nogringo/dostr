import 'package:dostr_core/dostr_core.dart';

/// NIP-01 address shared by every version of a replaceable or addressable
/// [event], or `null` for any other kind.
String? replaceableAddress(Nip01Event event) {
  final kind = event.kind;
  if (!EventKindClassification.isReplaceableKind(kind)) return null;
  final dTag = EventKindClassification.isAddressableKind(kind)
      ? event.dTag ?? ''
      : '';
  return '$kind:${event.pubkey}:$dTag';
}

/// Whether relays keep [a] over [b], two versions sharing an address: the
/// latest `created_at` wins, then the lowest id (NIP-01).
bool replaces(Nip01Event a, Nip01Event b) => a.createdAt != b.createdAt
    ? a.createdAt > b.createdAt
    : a.id.compareTo(b.id) < 0;
