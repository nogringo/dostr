import 'dart:typed_data';

import 'package:convert/convert.dart';

typedef _Point = ({BigInt x, BigInt y, BigInt z});

final _fieldPrime = BigInt.parse(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
  radix: 16,
);
final _curveOrder = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);
final _low256Bits = (BigInt.one << 256) - BigInt.one;
final _foldFactor = BigInt.parse('1000003d1', radix: 16);
final _three = BigInt.from(3);
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
  if (scalar == BigInt.zero || scalar >= _curveOrder) {
    throw const FormatException('Not a valid private key');
  }
  final x = _multiplyX(scalar, _decodePublicKey(publicKey));
  return Uint8List.fromList(hex.decode(x.toRadixString(16).padLeft(64, '0')));
}

_Point _decodePublicKey(String publicKey) {
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
      (x.modPow(_three, _fieldPrime) + BigInt.from(7)) % _fieldPrime;

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
  return (x: x, y: y, z: BigInt.one);
}

/// The affine x of [scalar] times [point], with a fixed 4-bit window in
/// Jacobian coordinates so that it inverts only once.
BigInt _multiplyX(BigInt scalar, _Point point) {
  final multiples = [point, _double(point)];
  while (multiples.length < 15) {
    multiples.add(_add(multiples.last, point));
  }
  final digits = scalar
      .toRadixString(16)
      .split('')
      .map((digit) => int.parse(digit, radix: 16))
      .toList();

  // Every partial sum stays below the curve order, so _add never meets two
  // equal or opposite points.
  var result = multiples[digits.first - 1];
  for (final digit in digits.skip(1)) {
    result = _double(_double(_double(_double(result))));
    if (digit != 0) {
      result = _add(result, multiples[digit - 1]);
    }
  }
  final zInverse = result.z.modInverse(_fieldPrime);
  return _reduce(_reduce(result.x * zInverse) * zInverse);
}

// dbl-2009-l, https://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html
_Point _double(_Point point) {
  final (:x, :y, :z) = point;
  final a = _reduce(x * x);
  final b = _reduce(y * y);
  final c = _reduce(b * b);
  final xb = x + b;
  final d = _reduce(_subMod(_reduce(xb * xb), _addMod(a, c)) << 1);
  final e = _reduce(a * _three);
  final x3 = _subMod(_reduce(e * e), _addMod(d, d));
  return (
    x: x3,
    y: _subMod(_reduce(e * _subMod(d, x3)), _reduce(c << 3)),
    z: _reduce((y * z) << 1),
  );
}

// add-2007-bl, https://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html
_Point _add(_Point p1, _Point p2) {
  final z1z1 = _reduce(p1.z * p1.z);
  final z2z2 = _reduce(p2.z * p2.z);
  final u1 = _reduce(p1.x * z2z2);
  final u2 = _reduce(p2.x * z1z1);
  final s1 = _reduce(_reduce(p1.y * p2.z) * z2z2);
  final s2 = _reduce(_reduce(p2.y * p1.z) * z1z1);
  final h = _subMod(u2, u1);
  final i = _reduce((h * h) << 2);
  final j = _reduce(h * i);
  final r = _reduce(_subMod(s2, s1) << 1);
  final v = _reduce(u1 * i);
  final x3 = _subMod(_reduce(r * r), _addMod(j, _addMod(v, v)));
  final zz = p1.z + p2.z;
  return (
    x: x3,
    y: _subMod(_reduce(r * _subMod(v, x3)), _reduce((s1 * j) << 1)),
    z: _reduce(_subMod(_reduce(zz * zz), _addMod(z1z1, z2z2)) * h),
  );
}

// p = 2^256 - 0x1000003d1, so the bits above 256 fold back in times
// 0x1000003d1. Faster than BigInt %, for any value below 2^515.
BigInt _reduce(BigInt value) {
  value = (value & _low256Bits) + (value >> 256) * _foldFactor;
  value = (value & _low256Bits) + (value >> 256) * _foldFactor;
  return value >= _fieldPrime ? value - _fieldPrime : value;
}

BigInt _addMod(BigInt a, BigInt b) {
  final sum = a + b;
  return sum >= _fieldPrime ? sum - _fieldPrime : sum;
}

BigInt _subMod(BigInt a, BigInt b) {
  final difference = a - b;
  return difference.isNegative ? difference + _fieldPrime : difference;
}
