/// The values of TLV (type-length-value) entries, by type, in order.
typedef TlvValues = Map<int, List<List<int>>>;

/// The bytes of a TLV entry. [value] holds at most 255 bytes.
List<int> tlvEntry(int type, List<int> value) => [type, value.length, ...value];

/// The TLV entries of [bytes]. Throws a [FormatException] when the last one is
/// cut short.
TlvValues parseTlv(List<int> bytes) {
  final values = <int, List<List<int>>>{};
  var index = 0;
  while (index < bytes.length) {
    if (index + 2 > bytes.length) {
      throw const FormatException('Truncated TLV entry');
    }
    final type = bytes[index];
    final end = index + 2 + bytes[index + 1];
    if (end > bytes.length) {
      throw const FormatException('Truncated TLV entry');
    }
    (values[type] ??= []).add(bytes.sublist(index + 2, end));
    index = end;
  }
  return values;
}
