import 'package:dostr_nip01/hex.dart';
import 'package:test/test.dart';

void main() {
  group('isLowercaseHex', () {
    test('accepts lowercase hex of the given length', () {
      expect(isLowercaseHex('0123456789abcdef', length: 16), isTrue);
    });

    test('accepts lowercase hex of any even length without a length', () {
      expect(isLowercaseHex(''), isTrue);
      expect(isLowercaseHex('00ff'), isTrue);
    });

    for (final value in ['0A', 'aG', '+a', '-1', ' a', 'a ']) {
      test('rejects "$value"', () {
        expect(isLowercaseHex(value), isFalse);
      });
    }

    test('rejects another length than the given one', () {
      expect(isLowercaseHex('abcd', length: 2), isFalse);
      expect(isLowercaseHex('ab', length: 4), isFalse);
    });

    test('rejects an odd length without a length', () {
      expect(isLowercaseHex('abc'), isFalse);
    });
  });

  group('bytesToHex', () {
    test('writes two lowercase digits per byte', () {
      expect(bytesToHex([0, 15, 16, 171, 255]), '000f10abff');
      expect(bytesToHex([]), '');
    });

    test('rejects a value that does not fit a byte', () {
      expect(() => bytesToHex([256]), throwsRangeError);
      expect(() => bytesToHex([-1]), throwsRangeError);
    });
  });

  group('hexToBytes', () {
    test('reads lowercase and uppercase hex', () {
      expect(hexToBytes('000f10abff'), [0, 15, 16, 171, 255]);
      expect(hexToBytes('ABff'), [171, 255]);
      expect(hexToBytes(''), isEmpty);
    });

    for (final value in ['abc', 'zz', '+f', '-1', ' a', 'g0']) {
      test('rejects "$value"', () {
        expect(() => hexToBytes(value), throwsFormatException);
      });
    }

    test('does not quote the hex in its error', () {
      const key =
          '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffz';
      expect(
        () => hexToBytes(key),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains(key.substring(0, 8))),
          ),
        ),
      );
    });
  });
}
