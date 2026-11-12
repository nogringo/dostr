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
}
