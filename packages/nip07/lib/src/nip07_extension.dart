/// What a `Nip07Signer` needs from `window.nostr`.
///
/// Every answer is the JavaScript value turned into Dart, as `dartify` does.
/// The extension turns a request down, or fails it, by throwing.
abstract interface class Nip07Extension {
  Future<Object?> getPublicKey();

  /// [event] is the unsigned event, as NIP-01 JSON.
  Future<Object?> signEvent(Map<String, Object?> event);

  /// null for an extension without NIP-04
  Nip07Cipher? get nip04;

  /// null for an extension without NIP-44
  Nip07Cipher? get nip44;
}

/// The `nip04` or `nip44` object of an extension.
abstract interface class Nip07Cipher {
  Future<Object?> encrypt(String recipientPubkey, String plaintext);

  Future<Object?> decrypt(String senderPubkey, String ciphertext);
}
