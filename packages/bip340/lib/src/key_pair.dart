/// A private key and its x-only public key, both 32 bytes in hex.
class KeyPair {
  final String privateKey;

  final String publicKey;

  const KeyPair(this.privateKey, this.publicKey);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyPair &&
          runtimeType == other.runtimeType &&
          publicKey == other.publicKey;

  @override
  int get hashCode => publicKey.hashCode;
}
