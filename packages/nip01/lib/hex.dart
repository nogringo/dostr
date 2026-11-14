/// The lowercase hex that NIP-01 requires for ids, pubkeys and signatures:
/// a check for event verifiers to run before they decode it, and the
/// conversions between bytes and hex.
library;

import 'dart:typed_data';

const _digits = '0123456789abcdef';

/// Whether [value] is lowercase hex, of [length] characters when given and of
/// an even length otherwise.
bool isLowercaseHex(String value, {int? length}) {
  if (length == null ? value.length.isOdd : value.length != length) {
    return false;
  }
  for (final unit in value.codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLowercaseLetter = unit >= 0x61 && unit <= 0x66;
    if (!isDigit && !isLowercaseLetter) return false;
  }
  return true;
}

/// [bytes] as lowercase hex. Throws a [RangeError] when one of them does not
/// fit a byte.
String bytesToHex(List<int> bytes) {
  final hex = StringBuffer();
  for (final byte in bytes) {
    RangeError.checkValueInInterval(byte, 0, 0xff, 'bytes');
    hex
      ..write(_digits[byte >> 4])
      ..write(_digits[byte & 0xf]);
  }
  return hex.toString();
}

/// The bytes of [hex], in lowercase or uppercase. Throws a [FormatException]
/// when it is not an even number of hex digits.
Uint8List hexToBytes(String hex) {
  if (hex.length.isOdd) {
    throw const FormatException('Hex has an odd number of digits');
  }
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] =
        _digitValue(hex.codeUnitAt(2 * i)) << 4 |
        _digitValue(hex.codeUnitAt(2 * i + 1));
  }
  return bytes;
}

// No message quotes the hex: it may be a private key.
int _digitValue(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  final lowercase = unit | 0x20;
  if (lowercase >= 0x61 && lowercase <= 0x66) return lowercase - 0x57;
  throw const FormatException('Not a hex digit');
}
