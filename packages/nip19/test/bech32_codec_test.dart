import 'package:dostr_nip19/src/bech32_codec.dart';
import 'package:test/test.dart';

void main() {
  group('BIP-173 vectors', () {
    const valid = [
      'A12UEL5L',
      'a12uel5l',
      'an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs',
      'abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw',
      '11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j',
      'split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w',
      '?1ezyfcl',
    ];
    for (final input in valid) {
      test('decodes $input and encodes it back', () {
        final (prefix, bytes) = decodeBech32(input);

        expect(encodeBech32(prefix, bytes), input.toLowerCase());
      });
    }

    const invalid = [
      ('a prefix character below the range', '\x201nwldj5'),
      ('a prefix character above the range', '\x7f1axkwrx'),
      ('a prefix character outside ASCII', '\x801eym55h'),
      ('no separator', 'pzry9x0s0muk'),
      ('an empty prefix', '1pzry9x0s0muk'),
      ('an empty prefix and an invalid character', '10a06t8'),
      ('an empty prefix and a checksum only', '1qzzfhee'),
      ('an invalid data character', 'x1b4n0q5v'),
      ('a too short checksum', 'li1dgmt3'),
      ('an invalid checksum character', 'de1lg7wt\xff'),
      ('a checksum of the uppercase prefix', 'A1G7SGD8'),
    ];
    for (final (name, input) in invalid) {
      test('rejects $name', () {
        expect(() => decodeBech32(input), throwsFormatException);
      });
    }
  });

  group('length', () {
    test('accepts 5000 characters', () {
      final input = encodeBech32('x', List.filled(3120, 0));

      expect(input, hasLength(5000));
      expect(decodeBech32(input).$2, hasLength(3120));
    });

    test('rejects more than 5000 characters', () {
      final input = encodeBech32('x', List.filled(3121, 0));

      expect(input.length, greaterThan(5000));
      expect(() => decodeBech32(input), throwsFormatException);
    });
  });
}
