import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'nip44.dart';
import 'utils.dart';

/// The deprecated NIP-04 encryption, AES-CBC with no MAC: use `Nip44` unless
/// the peer does not support it.
class Nip04 {
  /// Encrypts [text] from the hex private key [priv] to the hex public key
  /// [pub], as `<ciphertext>?iv=<iv>`.
  static String encrypt(String priv, String pub, String text) {
    final iv = secureRandomBytes(16);
    final ciphertext = _aesCbc(true, priv, pub, iv).process(utf8.encode(text));
    return '${base64.encode(ciphertext)}?iv=${base64.encode(iv)}';
  }

  /// Decrypts a `<ciphertext>?iv=<iv>` [text], or returns an empty string when
  /// it has no `?iv=`.
  static String decrypt(String priv, String pub, String text) {
    final parts = text.split('?iv=');
    if (parts.length != 2) {
      return '';
    }
    final cipher = _aesCbc(false, priv, pub, base64.decode(parts[1]));
    return utf8.decode(cipher.process(base64.decode(parts[0])));
  }

  static PaddedBlockCipher _aesCbc(
    bool forEncryption,
    String priv,
    String pub,
    Uint8List iv,
  ) {
    final key = Nip44.computeSharedSecret(priv, pub);
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
