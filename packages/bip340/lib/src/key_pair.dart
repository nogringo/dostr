class KeyPair {
  /// [privateKey] is a 32-bytes hex-encoded string
  String? privateKey;

  /// [publicKey] is a 32-bytes hex-encoded string
  final String publicKey;

  KeyPair(this.privateKey, this.publicKey);

  KeyPair.justPublicKey(this.publicKey);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyPair &&
          runtimeType == other.runtimeType &&
          publicKey == other.publicKey;

  @override
  int get hashCode => publicKey.hashCode;
}
