import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'ecdh.dart';
import 'utils.dart';

/// The deprecated NIP-04 encryption, AES-CBC with no MAC: use `Nip44` unless
/// the peer does not support it.
/// https://github.com/nostr-protocol/nips/blob/master/04.md
///
/// Keys are hex strings, as for `Nip44`, and an invalid one throws a
/// [FormatException].
class Nip04 {
  /// Encrypts [plaintext] from [senderPrivateKey] to [recipientPublicKey], as
  /// `<ciphertext>?iv=<iv>`.
  static String encrypt(
    String plaintext,
    String senderPrivateKey,
    String recipientPublicKey,
  ) {
    final iv = secureRandomBytes(16);
    final cipher = _aesCbc(
      true,
      sharedSecret(senderPrivateKey, recipientPublicKey),
      iv,
    );
    final ciphertext = cipher.process(utf8.encode(plaintext));
    return '${base64.encode(ciphertext)}?iv=${base64.encode(iv)}';
  }

  /// Decrypts a `<ciphertext>?iv=<iv>` [payload] from [senderPublicKey] to
  /// [recipientPrivateKey].
  ///
  /// Throws a [FormatException] when [payload] is malformed, or does not
  /// decrypt with these keys. With no MAC, an altered payload can also decrypt
  /// to the wrong text.
  static String decrypt(
    String payload,
    String recipientPrivateKey,
    String senderPublicKey,
  ) {
    final parts = payload.split('?iv=');
    if (parts.length != 2) {
      throw const FormatException('Not a NIP-04 payload: it needs one ?iv=');
    }
    final ciphertext = base64.decode(parts[0]);
    final iv = base64.decode(parts[1]);
    if (ciphertext.isEmpty || ciphertext.length % 16 != 0) {
      throw const FormatException('The ciphertext is not whole AES blocks');
    }
    if (iv.length != 16) {
      throw const FormatException('The IV is not 16 bytes');
    }
    final cipher = _aesCbc(
      false,
      sharedSecret(recipientPrivateKey, senderPublicKey),
      iv,
    );
    final Uint8List plaintext;
    try {
      plaintext = cipher.process(ciphertext);
    } on ArgumentError {
      throw const FormatException(
        'Invalid padding: the keys do not match, or the payload was altered',
      );
    }
    return utf8.decode(plaintext);
  }

  static PaddedBlockCipher _aesCbc(
    bool forEncryption,
    Uint8List key,
    Uint8List iv,
  ) {
    return PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        forEncryption,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
  }
}
