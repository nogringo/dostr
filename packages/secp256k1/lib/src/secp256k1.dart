import 'dart:math';
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
final _n = secp256k1Order;
final _low256Bits = (BigInt.one << 256) - BigInt.one;
final _foldFactor = BigInt.parse('1000003d1', radix: 16);
final _three = BigInt.from(3);
final _seven = BigInt.from(7);

// GLV (Gallant, Lambert and Vanstone, 2001): lambda * (x, y) = (beta * x, y),
// and a1, b1, a2 split a scalar into two of about 128 bits.
final _beta = BigInt.parse(
  '7ae96a2b657c07106e64479eac3434e99cf0497512f58995c1396c28719501ee',
  radix: 16,
);
final _glvA1 = BigInt.parse('3086d221a7d46bcde86c90e49284eb15', radix: 16);
final _glvMinusB1 = BigInt.parse('e4437ed6010e88286f547fa90abfe4c3', radix: 16);
final _glvA2 = BigInt.parse('114ca50f7a8e2f3f657c1108d9d44cfd8', radix: 16);

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
    final normalized = _normalized(this, _z.modInverse(_p));
    return (x: normalized._x, y: normalized._y);
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
    final reduced = scalar % _n;
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

/// The hex digits of [scalar], at least [length] of them, most significant
/// first.
List<int> _nibbles(BigInt scalar, [int length = 0]) => [
  for (final unit in scalar.toRadixString(16).padLeft(length, '0').codeUnits)
    unit <= 0x39 ? unit - 0x30 : unit - 0x57,
];

/// k1 and k2 with k = k1 + k2 * lambda modulo n.
(BigInt, BigInt) _splitScalar(BigInt scalar) {
  final half = _n >> 1;
  final c1 = (_glvA1 * scalar + half) ~/ _n;
  final c2 = (_glvMinusB1 * scalar + half) ~/ _n;
  return (scalar - c1 * _glvA1 - c2 * _glvA2, c1 * _glvMinusB1 - c2 * _glvA1);
}

Secp256k1Point _endomorphism(Secp256k1Point point) =>
    Secp256k1Point._(_reduce(point._x * _beta), point._y, point._z);

Secp256k1Point _multiply(Secp256k1Point point, BigInt scalar) {
  final (k1, k2) = _splitScalar(scalar);
  final multiples = [point, _double(point)];
  while (multiples.length < 15) {
    multiples.add(_add(multiples.last, point));
  }
  final firstMultiples = [
    for (final multiple in multiples) k1.isNegative ? -multiple : multiple,
  ];
  final secondMultiples = [
    for (final multiple in multiples)
      k2.isNegative ? -_endomorphism(multiple) : _endomorphism(multiple),
  ];
  final length = max(
    k1.abs().toRadixString(16).length,
    k2.abs().toRadixString(16).length,
  );
  final firstDigits = _nibbles(k1.abs(), length);
  final secondDigits = _nibbles(k2.abs(), length);

  var result = Secp256k1Point.infinity;
  for (var i = 0; i < length; i++) {
    result = _double(_double(_double(_double(result))));
    if (firstDigits[i] != 0) {
      result = _add(result, firstMultiples[firstDigits[i] - 1]);
    }
    if (secondDigits[i] != 0) {
      result = _add(result, secondMultiples[secondDigits[i] - 1]);
    }
  }
  return result;
}

// _generatorTable[i][j - 1] is j * 16^i * G, in affine coordinates so that
// every addition is a mixed one, and k * G needs no doubling.
final _generatorTable = () {
  final multiples = <Secp256k1Point>[];
  var base = Secp256k1Point.generator;
  for (var i = 0; i < 64; i++) {
    final row = [base];
    while (row.length < 15) {
      row.add(_add(row.last, base));
    }
    multiples.addAll(row);
    base = _double(row[7]);
  }
  final affine = _toAffineAll(multiples);
  return [for (var i = 0; i < 64; i++) affine.sublist(i * 15, i * 15 + 15)];
}();

/// [points], none of them the point at infinity, with z = 1, for a single
/// inversion (Montgomery's trick).
List<Secp256k1Point> _toAffineAll(List<Secp256k1Point> points) {
  final products = <BigInt>[];
  var product = BigInt.one;
  for (final point in points) {
    product = _reduce(product * point._z);
    products.add(product);
  }
  var inverse = product.modInverse(_p);
  final zInverses = List.filled(points.length, BigInt.zero);
  for (var i = points.length - 1; i >= 0; i--) {
    zInverses[i] = i == 0 ? inverse : _reduce(inverse * products[i - 1]);
    inverse = _reduce(inverse * points[i]._z);
  }
  return [
    for (final (i, point) in points.indexed) _normalized(point, zInverses[i]),
  ];
}

/// [point] with z = 1, given the inverse of its z.
Secp256k1Point _normalized(Secp256k1Point point, BigInt zInverse) {
  final zInverse2 = _reduce(zInverse * zInverse);
  return Secp256k1Point._(
    _reduce(point._x * zInverse2),
    _reduce(_reduce(point._y * zInverse2) * zInverse),
    BigInt.one,
  );
}

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
  if (p2._z == BigInt.one) {
    return _addAffine(p1, p2);
  }
  if (p1._z == BigInt.one) {
    return _addAffine(p2, p1);
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

// madd-2007-bl, https://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html
Secp256k1Point _addAffine(Secp256k1Point p1, Secp256k1Point affine) {
  final z1z1 = _reduce(p1._z * p1._z);
  final u2 = _reduce(affine._x * z1z1);
  final s2 = _reduce(_reduce(affine._y * p1._z) * z1z1);
  final h = _subMod(u2, p1._x);
  final r = _reduce(_subMod(s2, p1._y) << 1);
  if (h == BigInt.zero) {
    return r == BigInt.zero ? _double(affine) : Secp256k1Point.infinity;
  }
  final hh = _reduce(h * h);
  final i = _reduce(hh << 2);
  final j = _reduce(h * i);
  final v = _reduce(p1._x * i);
  final x3 = _subMod(_reduce(r * r), _addMod(j, _addMod(v, v)));
  final zh = p1._z + h;
  return Secp256k1Point._(
    x3,
    _subMod(_reduce(r * _subMod(v, x3)), _reduce((p1._y * j) << 1)),
    _subMod(_reduce(zh * zh), _addMod(z1z1, hh)),
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
