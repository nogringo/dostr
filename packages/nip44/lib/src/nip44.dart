import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import 'utils.dart';

final _secp256k1 = ECCurve_secp256k1();
final _fieldPrime = BigInt.parse(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
  radix: 16,
);
final _hexPattern = RegExp(r'^[0-9a-fA-F]+$');

/// NIP-44 encryption and decryption functions.
class Nip44 {
  static Future<String> encryptMessage(
    String plaintext,
    String senderPrivateKey,
    String recipientPublicKey, {
    Uint8List? customNonce,
    Uint8List? customConversationKey,
  }) async {
    // Step 1: Compute Shared Secret
    final sharedSecret =
        customConversationKey ??
        computeSharedSecret(senderPrivateKey, recipientPublicKey);

    // Step 2: Derive Conversation Key
    final conversationKey =
        customConversationKey ?? deriveConversationKey(sharedSecret);

    // Step 3: Generate or Use Custom Nonce
    final nonce = customNonce ?? secureRandomBytes(32);

    // Step 4: Derive Message Keys
    final keys = deriveMessageKeys(conversationKey, nonce);
    final chachaKey = keys['chachaKey']!;
    final chachaNonce = keys['chachaNonce']!;
    final hmacKey = keys['hmacKey']!;

    // Step 5: Pad Plaintext
    final paddedPlaintext = pad(utf8.encode(plaintext));

    // Step 6: Encrypt
    final ciphertext = await encryptChaCha20(
      chachaKey,
      chachaNonce,
      paddedPlaintext,
    );

    // Step 7: Calculate MAC
    final mac = calculateMac(hmacKey, nonce, ciphertext);

    // Step 8: Construct Payload
    return constructPayload(nonce, ciphertext, mac);
  }

  static Future<String> decryptMessage(
    String payload,
    String recipientPrivateKey,
    String senderPublicKey, {
    Uint8List? customConversationKey,
  }) async {
    // Step 1: Compute Shared Secret
    final sharedSecret =
        customConversationKey ??
        computeSharedSecret(recipientPrivateKey, senderPublicKey);

    // Step 2: Derive Conversation Key
    final conversationKey =
        customConversationKey ?? deriveConversationKey(sharedSecret);

    // Step 3: Parse Payload
    final parsed = parsePayload(payload);
    final nonce = parsed['nonce'];
    final ciphertext = parsed['ciphertext'];
    final mac = parsed['mac'];

    // Step 4: Derive Message Keys
    final keys = deriveMessageKeys(conversationKey, nonce);
    final chachaKey = keys['chachaKey']!;
    final chachaNonce = keys['chachaNonce']!;
    final hmacKey = keys['hmacKey']!;

    // Step 5: Verify MAC
    verifyMac(hmacKey, nonce, ciphertext, mac);

    // Step 6: Decrypt
    final paddedPlaintext = await decryptChaCha20(
      chachaKey,
      chachaNonce,
      ciphertext,
    );

    // Step 7: Unpad Plaintext
    final plaintextBytes = unpad(paddedPlaintext);

    return utf8.decode(plaintextBytes);
  }

  static Uint8List computeSharedSecret(
    String privateKeyHex,
    String publicKeyHex,
  ) {
    final publicKey = _decodePublicKey(checkPublicKey(publicKeyHex));
    final privateKey = BigInt.parse(privateKeyHex, radix: 16);
    if (privateKey <= BigInt.zero || privateKey >= _secp256k1.n) {
      throw Exception('invalid private key');
    }
    final sharedX = (publicKey * privateKey)!.x!.toBigInteger()!;
    return Uint8List.fromList(
      hex.decode(sharedX.toRadixString(16).padLeft(64, '0')),
    );
  }

  static ECPoint _decodePublicKey(String publicKeyHex) {
    if (!_hexPattern.hasMatch(publicKeyHex)) {
      throw Exception('Invalid Public Key');
    }
    final prefix = publicKeyHex.substring(0, 2);
    final x = BigInt.parse(publicKeyHex.substring(2, 66), radix: 16);
    if (x >= _fieldPrime) {
      throw Exception('invalid public key X value');
    }
    final ySquared =
        (x.modPow(BigInt.from(3), _fieldPrime) + BigInt.from(7)) % _fieldPrime;

    BigInt y;
    if (prefix == '04') {
      if (publicKeyHex.length != 130) {
        throw Exception('Invalid Public Key');
      }
      y = BigInt.parse(publicKeyHex.substring(66), radix: 16);
    } else {
      // p = 3 mod 4, so this is the square root when one exists
      y = ySquared.modPow((_fieldPrime + BigInt.one) >> 2, _fieldPrime);
      if (y.isOdd != (prefix == '03')) {
        y = _fieldPrime - y;
      }
    }
    if (y >= _fieldPrime || y * y % _fieldPrime != ySquared) {
      throw Exception('public key is not on this curve');
    }
    return _secp256k1.curve.createPoint(x, y);
  }

  static Uint8List deriveConversationKey(Uint8List sharedSecret) {
    final salt = utf8.encode('nip44-v2');

    final conversationKey = hkdfExtract(
      ikm: sharedSecret,
      salt: Uint8List.fromList(salt),
    );

    return conversationKey;
  }
}
