class EventKindClassification {
  /// replaceable although below 10000: metadata (NIP-01) and contact list
  /// (NIP-02). Not channel metadata (41): NIP-01 makes kinds 4 to 44 regular.
  static const legacyReplaceableKinds = {0, 3};

  static bool isEphemeralKind(int kind) => kind >= 20000 && kind <= 29999;

  static bool isReplaceableKind(int kind) {
    if (legacyReplaceableKinds.contains(kind)) {
      return true;
    }

    return isRegularReplaceableKind(kind) || isAddressableKind(kind);
  }

  static bool isRegularReplaceableKind(int kind) {
    return kind >= 10000 && kind <= 19999;
  }

  static bool isAddressableKind(int kind) {
    return isParameterizedReplaceableKind(kind);
  }

  static bool isParameterizedReplaceableKind(int kind) {
    return kind >= 30000 && kind <= 39999;
  }
}
