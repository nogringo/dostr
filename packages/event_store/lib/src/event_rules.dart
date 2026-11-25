import 'package:dostr_nip01/dostr_nip01.dart';

const deletionKind = 5;
const giftWrapKind = 1059;

/// NIP-01 order: newest first, then the lower id.
int newestFirst(Nip01Event a, Nip01Event b) => a.createdAt != b.createdAt
    ? b.createdAt.compareTo(a.createdAt)
    : a.id.compareTo(b.id);

/// NIP-01: the newer wins, the lower id on a tie.
bool replaces(Nip01Event incoming, Nip01Event current) =>
    newestFirst(incoming, current) < 0;

String address(int kind, String pubkey, String dTag) =>
    '$kind:$pubkey:${EventKindClassification.isAddressableKind(kind) ? dTag : ''}';

/// The `kind:pubkey:d` that its versions share, or null for a regular or
/// ephemeral kind.
String? addressOf(Nip01Event event) =>
    EventKindClassification.isReplaceableKind(event.kind)
    ? address(event.kind, event.pubkey, event.dTag ?? '')
    : null;

/// NIP-40: expired from its `expiration` second on.
bool isExpired(Nip01Event event, int now) {
  final expiration = int.tryParse(event.getFirstTag('expiration') ?? '');
  return expiration != null && expiration <= now;
}

/// NIP-09, and NIP-59 for a gift wrap, whose recipient deletes it.
bool canDelete(Nip01Event deletion, Nip01Event target) =>
    target.kind != deletionKind &&
    (target.pubkey == deletion.pubkey ||
        (target.kind == giftWrapKind &&
            target.getFirstTag('p') == deletion.pubkey));

/// The addresses of the `a` tags of [deletion] that its author owns.
Iterable<String> deletedAddresses(Nip01Event deletion) sync* {
  for (final coordinate in deletion.getTags('a')) {
    final parts = coordinate.split(':');
    if (parts.length < 2 || parts[1] != deletion.pubkey) continue;
    final kind = int.tryParse(parts[0]);
    if (kind == null ||
        '$kind' != parts[0] ||
        !EventKindClassification.isReplaceableKind(kind)) {
      continue;
    }
    yield address(kind, deletion.pubkey, parts.skip(2).join(':'));
  }
}

int nowInSeconds(DateTime now) => now.millisecondsSinceEpoch ~/ 1000;
