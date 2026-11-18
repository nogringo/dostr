import 'dart:convert';
import 'dart:typed_data';

import 'ecdh.dart';
import 'utils.dart';

/// Thrown by [Nip44.decrypt] and [Nip44.decryptMessage] when the payload was
/// altered after it was made, or the keys do not match.
class Nip44InvalidMacException implements Exception {
  const Nip44InvalidMacException();

  @override
  String toString() =>
      'Nip44InvalidMacException: the payload was altered, or the keys do not '
      'match';
}

/// NIP-44 v2 encryption.
/// https://github.com/nostr-protocol/nips/blob/master/44.md
///
/// Keys are hex strings. A public key is x-only (64 characters, as in Nostr
/// events) or SEC1 encoded. A key that is not valid on secp256k1 throws a
/// [FormatException].
class Nip44 {
  /// The conversation key between the hex [privateKey] and the hex
  /// [publicKey]: both peers get the same one.
  ///
  /// Compute it once per peer and pass it to [encrypt] and [decrypt] to skip
  /// the key agreement on each message.
  static Uint8List conversationKey({
    required String privateKey,
    required String publicKey,
  }) {
    return hkdfExtract(
      ikm: sharedSecret(privateKey, publicKey),
      salt: utf8.encode('nip44-v2'),
    );
  }

  /// Encrypts [plaintext], 1 to 4294967295 bytes in UTF-8, with
  /// [conversationKey] into a base64 NIP-44 payload.
  ///
  /// Throws an [ArgumentError] when [plaintext] is empty or too long.
  /// [nonce] is for test vectors only: a nonce must never be reused.
  static String encrypt(
    String plaintext,
    Uint8List conversationKey, {
    Uint8List? nonce,
  }) {
    nonce ??= secureRandomBytes(32);
    final keys = deriveMessageKeys(conversationKey, nonce);
    final ciphertext = chaCha20(
      keys.chachaKey,
      keys.chachaNonce,
      pad(utf8.encode(plaintext)),
    );
    return constructPayload(
      nonce,
      ciphertext,
      calculateMac(keys.hmacKey, nonce, ciphertext),
    );
  }

  /// Decrypts a NIP-44 [payload] with [conversationKey].
  ///
  /// Throws [Nip44InvalidMacException] when the payload was altered or the
  /// keys do not match, and a [FormatException] when [payload] is not a valid
  /// NIP-44 v2 payload.
  ///
  /// It decodes the whole [payload] in memory, with no size limit of its own:
  /// bound the size of a payload from an untrusted source before calling it.
  static String decrypt(String payload, Uint8List conversationKey) {
    final (:nonce, :ciphertext, :mac) = parsePayload(payload);
    final keys = deriveMessageKeys(conversationKey, nonce);
    if (!macMatches(keys.hmacKey, nonce, ciphertext, mac)) {
      throw const Nip44InvalidMacException();
    }
    return utf8.decode(
      unpad(chaCha20(keys.chachaKey, keys.chachaNonce, ciphertext)),
    );
  }

  /// Encrypts [plaintext] from [senderPrivateKey] to [recipientPublicKey], as
  /// [encrypt] does.
  static String encryptMessage(
    String plaintext, {
    required String senderPrivateKey,
    required String recipientPublicKey,
  }) {
    return encrypt(
      plaintext,
      conversationKey(
        privateKey: senderPrivateKey,
        publicKey: recipientPublicKey,
      ),
    );
  }

  /// Decrypts a [payload] from [senderPublicKey] to [recipientPrivateKey], as
  /// [decrypt] does.
  static String decryptMessage(
    String payload, {
    required String recipientPrivateKey,
    required String senderPublicKey,
  }) {
    return decrypt(
      payload,
      conversationKey(
        privateKey: recipientPrivateKey,
        publicKey: senderPublicKey,
      ),
    );
  }
}
