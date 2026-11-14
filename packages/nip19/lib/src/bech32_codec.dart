import 'package:bech32/bech32.dart';

/// The prefix and the bytes of the bech32 string [input]. Throws a
/// [FormatException] when it is not one.
(String, List<int>) decodeBech32(String input) {
  final Bech32 result;
  // No message quotes the input, nor the bech32 exception, which does: the
  // input may be a private key.
  try {
    result = const Bech32Codec().decode(input, input.length);
  } on Exception catch (e) {
    throw FormatException(switch (e) {
      MixedCase() => 'Not bech32: mixed case',
      InvalidChecksum() => 'Not bech32: invalid checksum',
      OutOfBoundChars() ||
      OutOfRangeHrpCharacters() => 'Not bech32: invalid character',
      _ => 'Not bech32',
    });
  }
  return (result.hrp, _convertBits(result.data, 5, 8, pad: false));
}

/// [bytes] as a bech32 string starting with [prefix].
String encodeBech32(String prefix, List<int> bytes) {
  final data = _convertBits(bytes, 8, 5, pad: true);
  return const Bech32Codec().encode(
    Bech32(prefix, data),
    prefix.length +
        separator.length +
        data.length +
        Bech32Validations.checksumLength,
  );
}

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
