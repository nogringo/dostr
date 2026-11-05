/// Regroups [from]-bit values into [to]-bit values, as in BIP-173.
List<int> convertBits(List<int> data, int from, int to, {required bool pad}) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxValue = (1 << to) - 1;
  final maxAcc = (1 << (from + to - 1)) - 1;

  for (final value in data) {
    if (value < 0 || value >> from != 0) {
      throw FormatException('Value out of range', value);
    }
    acc = ((acc << from) | value) & maxAcc;
    bits += from;
    while (bits >= to) {
      bits -= to;
      result.add((acc >> bits) & maxValue);
    }
  }

  if (pad) {
    if (bits > 0) result.add((acc << (to - bits)) & maxValue);
  } else if (bits >= from || ((acc << (to - bits)) & maxValue) != 0) {
    throw const FormatException('Invalid padding');
  }
  return result;
}
