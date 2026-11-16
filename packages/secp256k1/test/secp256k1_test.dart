import 'dart:math';

import 'package:dostr_secp256k1/dostr_secp256k1.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:test/test.dart';

BigInt _hex(String value) => BigInt.parse(value, radix: 16);

void main() {
  final g = Secp256k1Point.generator;
  final n = secp256k1Order;
  final p = secp256k1FieldPrime;
  final reference = ECCurve_secp256k1();
  final random = Random(256);

  BigInt randomScalar() =>
      _hex(
            List.generate(
              64,
              (_) => random.nextInt(16).toRadixString(16),
            ).join(),
          ) %
          (n - BigInt.one) +
      BigInt.one;

  void expectSame(Secp256k1Point actual, ECPoint expected) {
    expect(actual.x, expected.x!.toBigInteger());
    expect(actual.y, expected.y!.toBigInteger());
  }

  group('generator', () {
    test('is on the curve', () {
      expect(Secp256k1Point.fromXY(g.x, g.y), g);
    });

    test('has the known multiples 2G and 3G', () {
      expect(
        (g * BigInt.two).x,
        _hex(
          'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5',
        ),
      );
      expect(
        (g * BigInt.from(3)).x,
        _hex(
          'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9',
        ),
      );
    });

    test('has order n', () {
      expect((g * n).isInfinity, isTrue);
      expect((g * BigInt.zero).isInfinity, isTrue);
      final last = g * (n - BigInt.one);
      expect(last.x, g.x);
      expect(last.y, p - g.y);
      expect((g + last).isInfinity, isTrue);
    });
  });

  group('multiplication', () {
    final lambda = _hex(
      '5363ad4cc05c30e0a5261c028812645a122e22ea20816678df02967c1b23bd72',
    );
    final scalars = [
      for (final small in [1, 2, 15, 16, 17, 255, 256]) BigInt.from(small),
      BigInt.one << 128,
      BigInt.one << 255,
      lambda,
      lambda + BigInt.one,
      n - lambda,
      n - BigInt.two,
      n - BigInt.one,
      for (var i = 0; i < 40; i++) randomScalar(),
    ];

    test('by lambda multiplies x by beta, the GLV endomorphism', () {
      final beta = _hex(
        '7ae96a2b657c07106e64479eac3434e99cf0497512f58995c1396c28719501ee',
      );
      final point = g * randomScalar();
      expect(
        point * lambda,
        Secp256k1Point.fromXY(point.x * beta % p, point.y),
      );
    });

    test('of the generator matches pointycastle', () {
      for (final k in scalars) {
        expectSame(g * k, (reference.G * k)!);
      }
    });

    test('of any point matches pointycastle', () {
      final k = randomScalar();
      final point = g * k;
      final referencePoint = (reference.G * k)!;
      for (final scalar in scalars) {
        expectSame(point * scalar, (referencePoint * scalar)!);
      }
    });

    test('gives the same point through the table or the window', () {
      final copy = Secp256k1Point.fromXY(g.x, g.y)!;
      for (final k in scalars) {
        expect(copy * k, g * k);
      }
    });

    test('takes the scalar modulo n', () {
      expect(g * -BigInt.one, g * (n - BigInt.one));
      expect(g * (n + BigInt.two), g * BigInt.two);
    });

    test('of the point at infinity is the point at infinity', () {
      expect((Secp256k1Point.infinity * BigInt.two).isInfinity, isTrue);
    });
  });

  group('addition', () {
    test('doubles a point added to itself', () {
      final point = g * randomScalar();
      expect(point + point, point * BigInt.two);
    });

    test('has the point at infinity as identity', () {
      expect(g + Secp256k1Point.infinity, g);
      expect(Secp256k1Point.infinity + g, g);
    });

    test('matches pointycastle', () {
      for (var i = 0; i < 10; i++) {
        final a = randomScalar();
        final b = randomScalar();
        expectSame(g * a + g * b, ((reference.G * a)! + (reference.G * b))!);
      }
    });
  });

  group('fromX', () {
    test('picks the even y by default and the odd one on request', () {
      final point = g * randomScalar();
      final even = Secp256k1Point.fromX(point.x)!;
      final odd = Secp256k1Point.fromX(point.x, oddY: true)!;
      expect(even.y.isEven, isTrue);
      expect(odd.y.isOdd, isTrue);
      expect(even.y + odd.y, p);
    });

    test('rejects an x with no point', () {
      // BIP-340 test vector 5: "public key not on the curve"
      final x = _hex(
        'eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34',
      );
      expect(Secp256k1Point.fromX(x), isNull);
    });

    test('rejects an x that is not below p', () {
      expect(Secp256k1Point.fromX(p), isNull);
      expect(Secp256k1Point.fromX(-BigInt.one), isNull);
    });
  });

  group('fromXY', () {
    test('rejects a point off the curve', () {
      expect(Secp256k1Point.fromXY(g.x, g.y + BigInt.one), isNull);
    });

    test('rejects a coordinate that is not below p', () {
      expect(Secp256k1Point.fromXY(g.x, g.y + p), isNull);
    });
  });

  group('subtraction', () {
    test('matches the addition of the negation', () {
      final a = g * randomScalar();
      final b = g * randomScalar();
      expect(a - b + b, a);
      expect((a - a).isInfinity, isTrue);
      expect(-(-a), a);
      expect(-a, a * (n - BigInt.one));
    });
  });

  group('SEC1', () {
    test('round trips compressed and uncompressed points', () {
      for (var i = 0; i < 10; i++) {
        final point = g * randomScalar();
        for (final compressed in [true, false]) {
          final encoded = point.toSec1(compressed: compressed);
          expect(encoded.length, compressed ? 33 : 65);
          expect(Secp256k1Point.fromSec1(encoded), point);
        }
      }
    });

    test('matches pointycastle', () {
      final k = randomScalar();
      final referencePoint = (reference.G * k)!;
      for (final compressed in [true, false]) {
        expect(
          (g * k).toSec1(compressed: compressed),
          referencePoint.getEncoded(compressed),
        );
      }
    });

    test('rejects a prefix, a length or a point it does not know', () {
      final compressed = g.toSec1();
      expect(Secp256k1Point.fromSec1(compressed.sublist(1)), isNull);
      expect(Secp256k1Point.fromSec1([5, ...compressed.sublist(1)]), isNull);
      final uncompressed = g.toSec1(compressed: false);
      expect(
        Secp256k1Point.fromSec1([...uncompressed.sublist(0, 64), 0]),
        isNull,
      );
    });

    test('has no encoding for the point at infinity', () {
      expect(() => Secp256k1Point.infinity.toSec1(), throwsStateError);
    });
  });

  test('the point at infinity has no coordinates', () {
    expect(() => Secp256k1Point.infinity.x, throwsStateError);
    expect(() => Secp256k1Point.infinity.y, throwsStateError);
  });
}
