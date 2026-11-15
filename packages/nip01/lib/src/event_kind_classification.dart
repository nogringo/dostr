/// The kind ranges of NIP-01: regular, replaceable, addressable and ephemeral.
class EventKindClassification {
  /// Replaceable although below 10000: metadata (NIP-01) and contact list
  /// (NIP-02). Not channel metadata (41): NIP-01 makes kinds 4 to 44 regular.
  static const legacyReplaceableKinds = {0, 3};

  /// Whether [kind] is ephemeral (20000 to 29999): relays do not store it.
  static bool isEphemeralKind(int kind) => kind >= 20000 && kind <= 29999;

  /// Whether a newer event of [kind] replaces an older one: a replaceable kind
  /// (10000 to 19999, 0 and 3) or an addressable one (30000 to 39999).
  static bool isReplaceableKind(int kind) {
    if (legacyReplaceableKinds.contains(kind)) {
      return true;
    }

    return isRegularReplaceableKind(kind) || isAddressableKind(kind);
  }

  /// Whether [kind] is in the replaceable range (10000 to 19999), which leaves
  /// out [legacyReplaceableKinds].
  static bool isRegularReplaceableKind(int kind) {
    return kind >= 10000 && kind <= 19999;
  }

  /// Whether [kind] is addressable (30000 to 39999): a newer event replaces an
  /// older one with the same pubkey, kind and `d` tag.
  static bool isAddressableKind(int kind) {
    return kind >= 30000 && kind <= 39999;
  }
}
