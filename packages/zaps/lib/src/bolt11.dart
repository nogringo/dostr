/// The amount of the BOLT11 [invoice], in millisats, or null when it names no
/// amount or is not an invoice.
int? bolt11AmountMsats(String invoice) {
  final lowercase = invoice.toLowerCase();
  // bech32 data never holds a 1, so the last one ends the human-readable part
  final separator = lowercase.lastIndexOf('1');
  if (separator < 0) return null;
  final match = _humanReadablePart.firstMatch(
    lowercase.substring(0, separator),
  );
  if (match == null) return null;
  final amount = BigInt.parse(match[1]!);
  final msats = switch (match[2]) {
    '' => amount * BigInt.from(100000000000),
    'm' => amount * BigInt.from(100000000),
    'u' => amount * BigInt.from(100000),
    'n' => amount * BigInt.from(100),
    'p' when amount % BigInt.from(10) == BigInt.zero =>
      amount ~/ BigInt.from(10),
    _ => null,
  };
  return msats == null || msats > _bitcoinSupplyMsats ? null : msats.toInt();
}

final _humanReadablePart = RegExp(r'^ln[a-z]+?(\d+)([munp]?)$');

final _bitcoinSupplyMsats = BigInt.from(21000000) * BigInt.from(100000000000);
