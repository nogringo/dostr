// BIP-173 bech32, with the 5000 character limit of NIP-19 instead of 90.

const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const _separator = '1';
const _checksumLength = 6;
const _generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];

/// The most characters NIP-19 allows in a bech32 string.
const maxBech32Length = 5000;

/// The length of the string [encodeBech32] makes of [byteCount] bytes and
/// [prefix].
int bech32Length(String prefix, int byteCount) =>
    prefix.length +
    _separator.length +
    (byteCount * 8 + 4) ~/ 5 +
    _checksumLength;

/// The prefix and the bytes of the bech32 string [input]. Throws a
/// [FormatException] when it is not one, or when it is longer than the 5000
/// characters NIP-19 allows.
(String, List<int>) decodeBech32(String input) {
  // No message quotes the input: it may be a private key.
  if (input.length > maxBech32Length) {
    throw const FormatException(
      'Not bech32: more than $maxBech32Length characters',
    );
  }
  // Checked before lowercasing, which turns the Kelvin sign U+212A into a k.
  if (input.codeUnits.any((unit) => unit < 33 || unit > 126)) {
    throw const FormatException('Not bech32: invalid character');
  }
  final lowercase = input.toLowerCase();
  if (lowercase != input && input.toUpperCase() != input) {
    throw const FormatException('Not bech32: mixed case');
  }
  final separator = lowercase.lastIndexOf(_separator);
  if (separator < 1 || lowercase.length - separator - 1 < _checksumLength) {
    throw const FormatException('Not bech32');
  }
  final prefix = lowercase.substring(0, separator);
  final data = <int>[];
  for (var i = separator + 1; i < lowercase.length; i++) {
    final value = _charset.indexOf(lowercase[i]);
    if (value < 0) throw const FormatException('Not bech32: invalid character');
    data.add(value);
  }
  if (_polymod([..._expandPrefix(prefix), ...data]) != 1) {
    throw const FormatException('Not bech32: invalid checksum');
  }
  final payload = data.sublist(0, data.length - _checksumLength);
  return (prefix, _convertBits(payload, 5, 8, pad: false));
}

/// [bytes] as a bech32 string starting with [prefix].
String encodeBech32(String prefix, List<int> bytes) {
  final data = _convertBits(bytes, 8, 5, pad: true);
  final polymod =
      _polymod([
        ..._expandPrefix(prefix),
        ...data,
        ...List.filled(_checksumLength, 0),
      ]) ^
      1;
  final checksum = [
    for (var i = 0; i < _checksumLength; i++)
      (polymod >> 5 * (_checksumLength - 1 - i)) & 31,
  ];
  final characters = [...data, ...checksum].map((value) => _charset[value]);
  return '$prefix$_separator${characters.join()}';
}

int _polymod(List<int> values) {
  var checksum = 1;
  for (final value in values) {
    final top = checksum >> 25;
    checksum = ((checksum & 0x1ffffff) << 5) ^ value;
    for (var i = 0; i < _generator.length; i++) {
      if ((top >> i) & 1 == 1) checksum ^= _generator[i];
    }
  }
  return checksum;
}

List<int> _expandPrefix(String prefix) => [
  for (final unit in prefix.codeUnits) unit >> 5,
  0,
  for (final unit in prefix.codeUnits) unit & 31,
];

List<int> _convertBits(List<int> data, int from, int to, {required bool pad}) {
  var accumulator = 0;
  var bits = 0;
  final result = <int>[];
  final maxValue = (1 << to) - 1;
  final maxAccumulator = (1 << (from + to - 1)) - 1;
  for (final value in data) {
    accumulator = ((accumulator << from) | value) & maxAccumulator;
    bits += from;
    while (bits >= to) {
      bits -= to;
      result.add((accumulator >> bits) & maxValue);
    }
  }
  if (pad) {
    if (bits > 0) result.add((accumulator << (to - bits)) & maxValue);
  } else if (bits >= from || ((accumulator << (to - bits)) & maxValue) != 0) {
    throw const FormatException('Not bech32: invalid padding');
  }
  return result;
}
