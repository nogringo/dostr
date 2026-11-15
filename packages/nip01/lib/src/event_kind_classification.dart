/// The kind ranges of NIP-01: regular, replaceable, addressable and ephemeral.
abstract final class EventKindClassification {
  // Not channel metadata (41): NIP-01 makes kinds 4 to 44 regular.
  static const _legacyReplaceableKinds = {0, 3};

  /// Whether [kind] is ephemeral (20000 to 29999): relays do not store it.
  static bool isEphemeralKind(int kind) => kind >= 20000 && kind <= 29999;

  /// Whether a newer event of [kind] replaces an older one: a replaceable kind
  /// (10000 to 19999, 0 and 3) or an addressable one (30000 to 39999).
  static bool isReplaceableKind(int kind) =>
      _legacyReplaceableKinds.contains(kind) ||
      (kind >= 10000 && kind <= 19999) ||
      isAddressableKind(kind);

  /// Whether [kind] is addressable (30000 to 39999): a newer event replaces an
  /// older one with the same pubkey, kind and `d` tag.
  static bool isAddressableKind(int kind) => kind >= 30000 && kind <= 39999;
}
