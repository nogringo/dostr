/// What `GiftWrap` throws when it cannot make or open a gift wrap.
sealed class GiftWrapException implements Exception {
  const GiftWrapException();
}

/// Thrown when a call has no custom signer or pubkey, and the `signer` of
/// `GiftWrap` returns null, such as when nobody is logged in.
final class GiftWrapNoSignerException extends GiftWrapException {
  const GiftWrapNoSignerException();

  @override
  String toString() =>
      'GiftWrapNoSignerException: no custom signer, and nobody to sign as';
}

/// Thrown when the signer cannot encrypt a seal or a wrap for
/// [recipientPubkey].
final class GiftWrapEncryptionException extends GiftWrapException {
  final String recipientPubkey;

  /// What the signer threw, or null when it returned no ciphertext.
  final Object? cause;

  const GiftWrapEncryptionException(this.recipientPubkey, {this.cause});

  @override
  String toString() =>
      'GiftWrapEncryptionException: cannot encrypt for $recipientPubkey'
      '${cause == null ? '' : ': $cause'}';
}

/// Thrown when the signer cannot decrypt the wrap or the seal [eventId]: it
/// is for someone else, or the signer failed.
final class GiftWrapDecryptionException extends GiftWrapException {
  final String eventId;

  /// What the signer threw, or null when it returned no plaintext.
  final Object? cause;

  const GiftWrapDecryptionException(this.eventId, {this.cause});

  @override
  String toString() =>
      'GiftWrapDecryptionException: cannot decrypt $eventId'
      '${cause == null ? '' : ': $cause'}';
}

/// Thrown when a decrypted gift wrap does not hold a valid seal and rumor: a
/// payload is not an event, or the seal's signature, the rumor's pubkey or the
/// rumor's id is wrong.
final class InvalidGiftWrapException extends GiftWrapException {
  /// What is wrong, such as "the seal's signature is invalid".
  final String reason;

  const InvalidGiftWrapException(this.reason);

  @override
  String toString() => 'InvalidGiftWrapException: $reason';
}
