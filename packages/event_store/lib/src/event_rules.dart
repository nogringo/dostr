import 'package:dostr_nip01/dostr_nip01.dart';

const deletionKind = 5;
const giftWrapKind = 1059;

/// Orders events as NIP-01 does: newest first, then the lower id.
int newestFirst(Nip01Event a, Nip01Event b) => a.createdAt != b.createdAt
    ? b.createdAt.compareTo(a.createdAt)
    : a.id.compareTo(b.id);

/// Whether [incoming] replaces [current], a version of the same address:
/// NIP-01 keeps the newer, and the lower id at the same `created_at`.
bool replaces(Nip01Event incoming, Nip01Event current) =>
    newestFirst(incoming, current) < 0;

/// The `kind:pubkey:d` that the versions of [event] share, with an empty `d`
/// for a replaceable kind, or null for a regular or ephemeral kind.
String? addressOf(Nip01Event event) =>
    EventKindClassification.isReplaceableKind(event.kind)
    ? _address(event.kind, event.pubkey, event.dTag ?? '')
    : null;

/// Whether [event] expired at [now], in seconds: NIP-40 expires it from its
/// `expiration` second on.
bool isExpired(Nip01Event event, int now) {
  final expiration = int.tryParse(event.getFirstTag('expiration') ?? '');
  return expiration != null && expiration <= now;
}

/// Whether [deletion], a `kind:5` whose `e` tags name [target], deletes it:
/// NIP-09 lets its author delete it, and NIP-59 the recipient of a gift wrap,
/// the pubkey of its `p` tag. A deletion request does not delete another one.
bool canDelete(Nip01Event deletion, Nip01Event target) =>
    target.kind != deletionKind &&
    (target.pubkey == deletion.pubkey ||
        (target.kind == giftWrapKind &&
            target.getFirstTag('p') == deletion.pubkey));

/// The addresses the `a` tags of [deletion] name, as [addressOf] gives them,
/// of its author and a replaceable or addressable kind only. Each deletes the
/// versions up to the `created_at` of [deletion].
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
    yield _address(kind, deletion.pubkey, parts.skip(2).join(':'));
  }
}

String _address(int kind, String pubkey, String dTag) =>
    '$kind:$pubkey:${EventKindClassification.isAddressableKind(kind) ? dTag : ''}';

int nowInSeconds(DateTime now) => now.millisecondsSinceEpoch ~/ 1000;
