import 'dart:typed_data';

const _digits = '0123456789abcdef';

/// The bytes of [hex], in lowercase or uppercase, or null when it is not an
/// even number of hex digits.
Uint8List? tryHexToBytes(String hex) {
  if (hex.length.isOdd) return null;
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final high = _digitValue(hex.codeUnitAt(2 * i));
    final low = _digitValue(hex.codeUnitAt(2 * i + 1));
    if (high < 0 || low < 0) {
      bytes.fillRange(0, bytes.length, 0);
      return null;
    }
    bytes[i] = high << 4 | low;
  }
  return bytes;
}

/// [bytes] as lowercase hex.
String bytesToHex(List<int> bytes) {
  final hex = StringBuffer();
  for (final byte in bytes) {
    hex
      ..write(_digits[byte >> 4])
      ..write(_digits[byte & 0xf]);
  }
  return hex.toString();
}

int _digitValue(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  final lowercase = unit | 0x20;
  if (lowercase >= 0x61 && lowercase <= 0x66) return lowercase - 0x57;
  return -1;
}
