import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

final _secp256k1 = ECCurve_secp256k1();
final _fieldPrime = BigInt.parse(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
  radix: 16,
);
final _privateKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _publicKeyPattern = RegExp(
  r'^(0[23][0-9a-fA-F]{64}|04[0-9a-fA-F]{128})$',
);

/// The x coordinate of the secp256k1 ECDH of the hex [privateKey] and the hex
/// [publicKey], x-only or SEC1 encoded.
///
/// Throws a [FormatException] when a key is not valid. It never holds the
/// private key.
Uint8List sharedSecret(String privateKey, String publicKey) {
  final scalar = _privateKeyPattern.hasMatch(privateKey)
      ? BigInt.parse(privateKey, radix: 16)
      : BigInt.zero;
  if (scalar == BigInt.zero || scalar >= _secp256k1.n) {
    throw const FormatException('Not a valid private key');
  }
  final x = (_decodePublicKey(publicKey) * scalar)!.x!.toBigInteger()!;
  return Uint8List.fromList(hex.decode(x.toRadixString(16).padLeft(64, '0')));
}

ECPoint _decodePublicKey(String publicKey) {
  final encoded = publicKey.length == 64 ? '02$publicKey' : publicKey;
  if (!_publicKeyPattern.hasMatch(encoded)) {
    throw FormatException('Not a valid public key', publicKey);
  }
  final x = BigInt.parse(encoded.substring(2, 66), radix: 16);
  if (x >= _fieldPrime) {
    throw FormatException(
      'Public key x is not below the field prime',
      publicKey,
    );
  }
  final ySquared =
      (x.modPow(BigInt.from(3), _fieldPrime) + BigInt.from(7)) % _fieldPrime;

  BigInt y;
  if (encoded.startsWith('04')) {
    y = BigInt.parse(encoded.substring(66), radix: 16);
  } else {
    // p = 3 mod 4, so this is the square root when one exists
    y = ySquared.modPow((_fieldPrime + BigInt.one) >> 2, _fieldPrime);
    if (y.isOdd != encoded.startsWith('03')) {
      y = _fieldPrime - y;
    }
  }
  if (y >= _fieldPrime || y * y % _fieldPrime != ySquared) {
    throw FormatException('Public key is not on secp256k1', publicKey);
  }
  return _secp256k1.curve.createPoint(x, y);
}
