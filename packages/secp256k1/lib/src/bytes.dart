import 'dart:typed_data';

final _byteMask = BigInt.from(0xff);

/// The unsigned big-endian integer of [bytes].
BigInt bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

/// [value], below 2^256, in 32 big-endian bytes.
Uint8List bigIntTo32Bytes(BigInt value) {
  final bytes = Uint8List(32);
  var rest = value;
  for (var i = 31; i >= 0; i--) {
    bytes[i] = (rest & _byteMask).toInt();
    rest >>= 8;
  }
  return bytes;
}
