class EventKindClassification {
  /// replaceable although below 10000: metadata (NIP-01), contact list
  /// (NIP-02) and channel metadata (NIP-28)
  static const legacyReplaceableKinds = {0, 3, 41};

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
