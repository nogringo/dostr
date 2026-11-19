# dostr_string_color

A color for any string or pubkey, as the String Color spec describes (the NIP-54 wiki article `string-color`, `naddr1qqx8xarjd9hxwttrdakx7uszypnqmrrcv50hqjr7exudms5ru2w0y4skj0w68w3yd5la8sydhdcgxqcyqqq8scsxffwu8`).
A string gets the same color in every client that follows the spec, and the colors read well as text, background, border or dot in dark and light themes.

## Install

```yaml
dependencies:
  dostr_string_color: ^0.1.0
```

## Usage

```dart
import 'package:dostr_string_color/dostr_string_color.dart';

final name = StringColor.fromText('alice'); // rgb(230, 69, 216)
final author = StringColor.fromHex(pubkey);
```

- `fromText` hashes a name, a label or any other text. It ignores case and surrounding whitespace, and hashes UTF-16 code units, as JavaScript's `charCodeAt` reads them. It trims and uppercases as JavaScript's `trim` and `toUpperCase` do, with Unicode 17, on every platform: `Straße` gets the color of `STRASSE` on the Dart VM too.
- `fromHex` reads a hex string, such as a pubkey, as one number.

Call the one that matches what you have: `fromText('Dad')` and `fromHex('Dad')` are two different colors.
An empty text, or a hex string with anything but hex digits, gets `StringColor.neutralGrey`, `rgb(128, 128, 128)`.

## Text

For a name or a mention drawn as text, adjust the color to the background, as the spec recommends: `forTextOnDark()` brightens it by 8% and `forTextOnLight()` darkens it by 5%.
Keep it as it is for a background, a border or an avatar.

## Rendering

`red`, `green` and `blue` hold the channels, from 0 to 255.
`toString()` gives the CSS form, `rgb(230, 69, 216)`, and `argb` the 32-bit value Flutter's `Color` takes.
`dostr_flutter` exports this package and adds `toColor()`:

```dart
final color = StringColor.fromHex(pubkey).toColor();
```

## Coming from `ndk_flutter`

`StringColor.fromString` read any string made of hex digits as a number, names such as "Dad" or "Bea" included.
Say which one you have instead:

| Before | After |
| ------ | ----- |
| `StringColor.fromString(pubkey)` | `StringColor.fromHex(pubkey).toColor()` |
| `StringColor.fromString(name)` | `StringColor.fromText(name).toColor()` |
| `StringColor.fromString(name, textBrightness: Brightness.dark)` | `StringColor.fromText(name).forTextOnDark().toColor()` |
| `StringColor.fromString(name, textBrightness: Brightness.light)` | `StringColor.fromText(name).forTextOnLight().toColor()` |
| `StringColor.neutralGrey` | `StringColor.neutralGrey.toColor()` |
