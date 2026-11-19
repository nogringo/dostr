import 'package:dostr_string_color/dostr_string_color.dart';
import 'package:test/test.dart';

// The expected colors come from a separate implementation of the spec, which
// keeps the full number as a big integer.
void main() {
  group('StringColor.fromText', () {
    test('gives neutral grey to an empty text', () {
      expect(StringColor.fromText(''), StringColor.neutralGrey);
      expect(StringColor.fromText('   '), StringColor.neutralGrey);
    });

    test('hashes the character codes', () {
      expect(StringColor.fromText('alice'), const StringColor(230, 69, 216));
      expect(StringColor.fromText('Bob'), const StringColor(83, 179, 54));
      expect(
        StringColor.fromText('hello world'),
        const StringColor(119, 73, 245),
      );
    });

    test('ignores case and surrounding whitespace', () {
      final bob = StringColor.fromText('Bob');
      expect(StringColor.fromText('bob'), bob);
      expect(StringColor.fromText('  BOB  '), bob);
    });

    test('hashes a text made of hex digits as text', () {
      expect(StringColor.fromText('ABC'), const StringColor(179, 122, 54));
      expect(StringColor.fromText('Dad'), const StringColor(54, 179, 129));
    });

    test('hashes UTF-16 code units', () {
      expect(StringColor.fromText('Élodie'), const StringColor(179, 69, 230));
      expect(StringColor.fromText('😀'), const StringColor(73, 105, 245));
    });

    test('trims as JavaScript does, on every platform', () {
      final bob = StringColor.fromText('Bob');
      expect(StringColor.fromText('\u{3000}Bob\u{FEFF}'), bob);
      expect(
        StringColor.fromText('Bob\u{85}'),
        const StringColor(54, 149, 179),
      );
    });

    test('uppercases as JavaScript does, on every platform', () {
      expect(StringColor.fromText('Straße'), const StringColor(230, 69, 125));
      expect(StringColor.fromText('ﬁ'), const StringColor(179, 133, 54));
      expect(StringColor.fromText('ნინო'), const StringColor(54, 179, 112));
    });

    test('matches the big integer hash on a long text', () {
      expect(
        StringColor.fromText(
          'The quick brown fox jumps over the lazy dog. ' * 40,
        ),
        const StringColor(230, 69, 101),
      );
    });
  });

  group('StringColor.fromHex', () {
    test('reads the hex as one number', () {
      expect(
        StringColor.fromHex(
          '660d8c78651f70487ec9b8ddc283e29cf2561693dda3ba246d3fd3c08dbb7083',
        ),
        const StringColor(57, 191, 189),
      );
      expect(StringColor.fromHex('deadbeef'), const StringColor(60, 191, 57));
      expect(StringColor.fromHex('ABC'), const StringColor(73, 108, 245));
      expect(StringColor.fromHex('Dad'), const StringColor(133, 73, 245));
    });

    test('ignores case', () {
      expect(StringColor.fromHex('DEADBEEF'), StringColor.fromHex('deadbeef'));
    });

    test('matches the big integer on a long hex', () {
      expect(StringColor.fromHex('f' * 1000), const StringColor(230, 109, 69));
    });

    test('gives neutral grey to an empty or invalid hex', () {
      for (final hex in ['', 'xyz', '0x1f', ' abc', '-1']) {
        expect(StringColor.fromHex(hex), StringColor.neutralGrey, reason: hex);
      }
    });
  });

  group('text adjustment', () {
    test('brightens by 8% on dark', () {
      expect(
        StringColor.fromText('alice').forTextOnDark(),
        const StringColor(248, 75, 233),
      );
    });

    test('darkens by 5% on light', () {
      expect(
        StringColor.fromText('alice').forTextOnLight(),
        const StringColor(219, 66, 205),
      );
    });

    test('clamps channels to 255', () {
      expect(
        StringColor.fromText('hello world').forTextOnDark(),
        const StringColor(129, 79, 255),
      );
    });
  });

  test('converts to ARGB and CSS', () {
    const color = StringColor(230, 69, 216);
    expect(color.argb, 0xFFE645D8);
    expect(color.toString(), 'rgb(230, 69, 216)');
  });
}
