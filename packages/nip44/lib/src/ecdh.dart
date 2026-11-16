import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:dostr_secp256k1/dostr_secp256k1.dart';

final _privateKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _publicKeyPattern = RegExp(
  r'^(0[23][0-9a-fA-F]{64}|04[0-9a-fA-F]{128})$',
);

/// The x coordinate of the secp256k1 ECDH of the hex [privateKey] and the hex
/// [publicKey], x-only or SEC1 encoded.
///
/// Throws a [FormatException] when a key is not valid. It never holds the
/// private key, and does not run in constant time.
Uint8List sharedSecret(String privateKey, String publicKey) {
  final scalar = _privateKeyPattern.hasMatch(privateKey)
      ? BigInt.parse(privateKey, radix: 16)
      : BigInt.zero;
  if (scalar == BigInt.zero || scalar >= secp256k1Order) {
    throw const FormatException('Not a valid private key');
  }
  final x = (_decodePublicKey(publicKey) * scalar).x;
  return Uint8List.fromList(hex.decode(x.toRadixString(16).padLeft(64, '0')));
}

Secp256k1Point _decodePublicKey(String publicKey) {
  final encoded = publicKey.length == 64 ? '02$publicKey' : publicKey;
  if (!_publicKeyPattern.hasMatch(encoded)) {
    throw FormatException('Not a valid public key', publicKey);
  }
  final x = BigInt.parse(encoded.substring(2, 66), radix: 16);
  if (x >= secp256k1FieldPrime) {
    throw FormatException(
      'Public key x is not below the field prime',
      publicKey,
    );
  }
  final point = encoded.startsWith('04')
      ? Secp256k1Point.fromXY(x, BigInt.parse(encoded.substring(66), radix: 16))
      : Secp256k1Point.fromX(x, oddY: encoded.startsWith('03'));
  return point ??
      (throw FormatException('Public key is not on secp256k1', publicKey));
}
