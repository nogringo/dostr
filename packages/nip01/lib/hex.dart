/// The lowercase hex that NIP-01 requires for ids, pubkeys and signatures,
/// for event verifiers to check before they decode it.
library;

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
