import 'dart:typed_data';

import 'bytes.dart';

/// The field prime p of secp256k1: every coordinate is below it.
final secp256k1FieldPrime = BigInt.parse(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
  radix: 16,
);

/// The order n of the secp256k1 group: a private key is between 1 and n - 1.
final secp256k1Order = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);

final _p = secp256k1FieldPrime;
final _low256Bits = (BigInt.one << 256) - BigInt.one;
final _foldFactor = BigInt.parse('1000003d1', radix: 16);
final _three = BigInt.from(3);
final _seven = BigInt.from(7);

/// A point of secp256k1, or the point at infinity.
///
/// The arithmetic runs in Jacobian coordinates: [x] and [y] cost a single
/// inversion, on first read. None of it runs in constant time.
final class Secp256k1Point {
  final BigInt _x;
  final BigInt _y;
  final BigInt _z;

  Secp256k1Point._(this._x, this._y, this._z);

  /// The generator G. Multiplying it uses a table of its multiples, built on
  /// first use.
  static final generator = Secp256k1Point._(
    BigInt.parse(
      '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
      radix: 16,
    ),
    BigInt.parse(
      '483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8',
      radix: 16,
    ),
    BigInt.one,
  );

  /// The point at infinity, the identity of the group.
  static final infinity = Secp256k1Point._(BigInt.one, BigInt.one, BigInt.zero);

  /// The point ([x], [y]), or null when it is not on the curve.
  static Secp256k1Point? fromXY(BigInt x, BigInt y) {
    if (!_isFieldElement(x) ||
        !_isFieldElement(y) ||
        _reduce(y * y) != _ySquared(x)) {
      return null;
    }
    return Secp256k1Point._(x, y, BigInt.one);
  }

  /// The point of x coordinate [x] with an odd y when [oddY] is true and an
  /// even one otherwise, as `lift_x` of BIP-340, or null when no point has
  /// this x.
  static Secp256k1Point? fromX(BigInt x, {bool oddY = false}) {
    if (!_isFieldElement(x)) {
      return null;
    }
    final ySquared = _ySquared(x);
    // p = 3 mod 4, so this is the square root when one exists
    var y = ySquared.modPow((_p + BigInt.one) >> 2, _p);
    if (_reduce(y * y) != ySquared) {
      return null;
    }
    if (y.isOdd != oddY) {
      y = _p - y;
    }
    return Secp256k1Point._(x, y, BigInt.one);
  }

  /// The point that [bytes] encode in SEC1, compressed in 33 bytes or not in
  /// 65, or null when they encode no point of the curve.
  static Secp256k1Point? fromSec1(List<int> bytes) {
    if (bytes.length == 33 && (bytes[0] == 2 || bytes[0] == 3)) {
      return fromX(bytesToBigInt(bytes.sublist(1)), oddY: bytes[0] == 3);
    }
    if (bytes.length == 65 && bytes[0] == 4) {
      return fromXY(
        bytesToBigInt(bytes.sublist(1, 33)),
        bytesToBigInt(bytes.sublist(33)),
      );
    }
    return null;
  }

  /// Whether this is the point at infinity, which has no coordinates.
  bool get isInfinity => _z == BigInt.zero;

  /// The affine x. Throws a [StateError] on the point at infinity.
  BigInt get x => _affine.x;

  /// The affine y. Throws a [StateError] on the point at infinity.
  BigInt get y => _affine.y;

  late final ({BigInt x, BigInt y}) _affine = _toAffine();

  ({BigInt x, BigInt y}) _toAffine() {
    if (isInfinity) {
      throw StateError('The point at infinity has no coordinates');
    }
    if (_z == BigInt.one) {
      return (x: _x, y: _y);
    }
    final zInverse = _z.modInverse(_p);
    final zInverse2 = _reduce(zInverse * zInverse);
    return (
      x: _reduce(_x * zInverse2),
      y: _reduce(_reduce(_y * zInverse2) * zInverse),
    );
  }

  /// This point in SEC1, compressed in 33 bytes unless [compressed] is false.
  /// Throws a [StateError] on the point at infinity.
  Uint8List toSec1({bool compressed = true}) => Uint8List.fromList([
    if (compressed) y.isOdd ? 3 : 2 else 4,
    ...bigIntTo32Bytes(x),
    if (!compressed) ...bigIntTo32Bytes(y),
  ]);

  Secp256k1Point operator +(Secp256k1Point other) => _add(this, other);

  Secp256k1Point operator -(Secp256k1Point other) => _add(this, -other);

  Secp256k1Point operator -() =>
      isInfinity ? this : Secp256k1Point._(_x, _subMod(BigInt.zero, _y), _z);

  /// This point times [scalar], taken modulo [secp256k1Order].
  Secp256k1Point operator *(BigInt scalar) {
    final reduced = scalar % secp256k1Order;
    if (reduced == BigInt.zero || isInfinity) {
      return infinity;
    }
    return identical(this, generator)
        ? _multiplyGenerator(reduced)
        : _multiply(this, reduced);
  }

  @override
  bool operator ==(Object other) =>
      other is Secp256k1Point &&
      (isInfinity
          ? other.isInfinity
          : !other.isInfinity && x == other.x && y == other.y);

  @override
  int get hashCode => isInfinity ? 0 : Object.hash(x, y);

  @override
  String toString() => isInfinity
      ? 'Secp256k1Point.infinity'
      : 'Secp256k1Point(${x.toRadixString(16)}, ${y.toRadixString(16)})';
}

bool _isFieldElement(BigInt value) => !value.isNegative && value < _p;

BigInt _ySquared(BigInt x) => _addMod(_reduce(_reduce(x * x) * x), _seven);

/// The hex digits of [scalar], most significant first.
List<int> _nibbles(BigInt scalar) => [
  for (final unit in scalar.toRadixString(16).codeUnits)
    unit <= 0x39 ? unit - 0x30 : unit - 0x57,
];

Secp256k1Point _multiply(Secp256k1Point point, BigInt scalar) {
  final multiples = [point, _double(point)];
  while (multiples.length < 15) {
    multiples.add(_add(multiples.last, point));
  }
  var result = Secp256k1Point.infinity;
  for (final digit in _nibbles(scalar)) {
    result = _double(_double(_double(_double(result))));
    if (digit != 0) {
      result = _add(result, multiples[digit - 1]);
    }
  }
  return result;
}

// _generatorTable[i][j - 1] is j * 16^i * G, so k * G needs no doubling.
final _generatorTable = () {
  final table = <List<Secp256k1Point>>[];
  var base = Secp256k1Point.generator;
  for (var i = 0; i < 64; i++) {
    final row = [base];
    while (row.length < 15) {
      row.add(_add(row.last, base));
    }
    table.add(row);
    base = _double(row[7]);
  }
  return table;
}();

Secp256k1Point _multiplyGenerator(BigInt scalar) {
  final digits = _nibbles(scalar);
  var result = Secp256k1Point.infinity;
  for (var i = 0; i < digits.length; i++) {
    final digit = digits[digits.length - 1 - i];
    if (digit != 0) {
      result = _add(result, _generatorTable[i][digit - 1]);
    }
  }
  return result;
}

// dbl-2009-l, https://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html
Secp256k1Point _double(Secp256k1Point point) {
  if (point.isInfinity) {
    return point;
  }
  final Secp256k1Point(_x: x, _y: y, _z: z) = point;
  final a = _reduce(x * x);
  final b = _reduce(y * y);
  final c = _reduce(b * b);
  final xb = x + b;
  final d = _reduce(_subMod(_reduce(xb * xb), _addMod(a, c)) << 1);
  final e = _reduce(a * _three);
  final x3 = _subMod(_reduce(e * e), _addMod(d, d));
  return Secp256k1Point._(
    x3,
    _subMod(_reduce(e * _subMod(d, x3)), _reduce(c << 3)),
    _reduce((y * z) << 1),
  );
}

// add-2007-bl, https://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html
Secp256k1Point _add(Secp256k1Point p1, Secp256k1Point p2) {
  if (p1.isInfinity) {
    return p2;
  }
  if (p2.isInfinity) {
    return p1;
  }
  final z1z1 = _reduce(p1._z * p1._z);
  final z2z2 = _reduce(p2._z * p2._z);
  final u1 = _reduce(p1._x * z2z2);
  final u2 = _reduce(p2._x * z1z1);
  final s1 = _reduce(_reduce(p1._y * p2._z) * z2z2);
  final s2 = _reduce(_reduce(p2._y * p1._z) * z1z1);
  final h = _subMod(u2, u1);
  final r = _reduce(_subMod(s2, s1) << 1);
  if (h == BigInt.zero) {
    return r == BigInt.zero ? _double(p1) : Secp256k1Point.infinity;
  }
  final i = _reduce((h * h) << 2);
  final j = _reduce(h * i);
  final v = _reduce(u1 * i);
  final x3 = _subMod(_reduce(r * r), _addMod(j, _addMod(v, v)));
  final zz = p1._z + p2._z;
  return Secp256k1Point._(
    x3,
    _subMod(_reduce(r * _subMod(v, x3)), _reduce((s1 * j) << 1)),
    _reduce(_subMod(_reduce(zz * zz), _addMod(z1z1, z2z2)) * h),
  );
}

// p = 2^256 - 0x1000003d1, so the bits above 256 fold back in times
// 0x1000003d1. Faster than BigInt %, for any value from 0 to 2^515.
BigInt _reduce(BigInt value) {
  value = (value & _low256Bits) + (value >> 256) * _foldFactor;
  value = (value & _low256Bits) + (value >> 256) * _foldFactor;
  return value >= _p ? value - _p : value;
}

BigInt _addMod(BigInt a, BigInt b) {
  final sum = a + b;
  return sum >= _p ? sum - _p : sum;
}

BigInt _subMod(BigInt a, BigInt b) {
  final difference = a - b;
  return difference.isNegative ? difference + _p : difference;
}
