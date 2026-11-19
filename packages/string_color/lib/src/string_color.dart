import 'upper_case_mapping.dart';

/// A color derived from a string as the String Color spec describes, as 8-bit
/// red, green and blue channels.
///
/// The spec is the NIP-54 wiki article `string-color`,
/// `naddr1qqx8xarjd9hxwttrdakx7uszypnqmrrcv50hqjr7exudms5ru2w0y4skj0w68w3yd5la8sydhdcgxqcyqqq8scsxffwu8`.
final class StringColor {
  /// A color of the given channels, each from 0 to 255.
  const StringColor(this.red, this.green, this.blue)
    : assert(
        0 <= red &&
            red <= 255 &&
            0 <= green &&
            green <= 255 &&
            0 <= blue &&
            blue <= 255,
      );

  /// The color of an empty or invalid input, `rgb(128, 128, 128)`.
  static const neutralGrey = StringColor(128, 128, 128);

  /// The color of [text], such as a name, hashed from the UTF-16 code units of
  /// its form trimmed and uppercased as JavaScript's `trim` and `toUpperCase`
  /// do.
  ///
  /// A [text] that is empty once trimmed gets [neutralGrey].
  factory StringColor.fromText(String text) {
    final normalized = _upperCase(text.replaceAll(_surroundingWhitespace, ''));
    if (normalized.isEmpty) return neutralGrey;

    // Reduced mod 360 at each step: the spec's BigInt hue, without the BigInt.
    var hue = 0;
    var weight = 1;
    for (final unit in normalized.codeUnits) {
      hue = (hue + unit * weight) % 360;
      weight = weight * 256 % 360;
    }
    return _fromHue(hue, warmValue: 0.70);
  }

  /// The color of [hex], such as a pubkey, read as one hexadecimal number.
  ///
  /// A [hex] that is empty or holds anything but hex digits gets
  /// [neutralGrey].
  factory StringColor.fromHex(String hex) {
    if (!_hexDigits.hasMatch(hex)) return neutralGrey;

    var hue = 0;
    for (var i = 0; i < hex.length; i++) {
      hue = (hue * 16 + int.parse(hex[i], radix: 16)) % 360;
    }
    return _fromHue(hue, warmValue: 0.75);
  }

  // Not String.trim, which also removes U+0085: `\s` is JavaScript's
  // whitespace on every platform.
  static final _surroundingWhitespace = RegExp(r'^\s+|\s+$');

  // Not String.toUpperCase: the Dart VM keeps ß and uses older Unicode data,
  // where JavaScript, and so Dart on the web, gives SS.
  static String _upperCase(String text) => text.runes
      .map((rune) => upperCaseMapping[rune] ?? String.fromCharCode(rune))
      .join();

  static final _hexDigits = RegExp(r'^[0-9a-fA-F]+$');

  static StringColor _fromHue(int hue, {required double warmValue}) {
    const saturation = 0.70;
    final value = switch (hue) {
      >= 32 && <= 204 => warmValue,
      >= 216 && <= 273 => 0.96,
      _ => 0.90,
    };

    final h = hue / 60;
    final c = value * saturation;
    final x = c * (1 - (h % 2 - 1).abs());
    final m = value - c;
    final (r, g, b) = switch (h.floor()) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };

    int channel(double t) => ((t + m) * 255).round();
    return StringColor(channel(r), channel(g), channel(b));
  }

  /// The red channel, from 0 to 255.
  final int red;

  /// The green channel, from 0 to 255.
  final int green;

  /// The blue channel, from 0 to 255.
  final int blue;

  /// This color brightened by 8%, for text on a dark background.
  StringColor forTextOnDark() => _scaled(1.08);

  /// This color darkened by 5%, for text on a light background.
  StringColor forTextOnLight() => _scaled(0.95);

  StringColor _scaled(double factor) {
    int scale(int channel) => (channel * factor).round().clamp(0, 255);
    return StringColor(scale(red), scale(green), scale(blue));
  }

  /// This color as an opaque 32-bit ARGB value, as Flutter's `Color` takes.
  int get argb => 0xFF000000 + (red << 16) + (green << 8) + blue;

  @override
  bool operator ==(Object other) =>
      other is StringColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(red, green, blue);

  /// This color in CSS form, such as `rgb(230, 69, 216)`.
  @override
  String toString() => 'rgb($red, $green, $blue)';
}
