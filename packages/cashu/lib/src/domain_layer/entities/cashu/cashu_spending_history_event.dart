enum CashuSpendDirection {
  sent('out'),
  received('in');

  final String value;

  const CashuSpendDirection(this.value);

  factory CashuSpendDirection.fromValue(String value) {
    return CashuSpendDirection.values.firstWhere(
      (transactionType) => transactionType.value == value,
      orElse: () => CashuSpendDirection.received,
    );
  }
}

enum CashuSpendMarker {
  /// A new token event was created
  created('created'),

  /// A token event was destroyed
  destroyed('destroyed'),

  /// A NIP-61 nutzap was redeemed
  redeemed('redeemed');

  final String value;

  const CashuSpendMarker(this.value);

  factory CashuSpendMarker.fromValue(String value) {
    return CashuSpendMarker.values.firstWhere(
      (t) => t.value == value,
      orElse: () => CashuSpendMarker.created,
    );
  }
}

class CashuSpendingHistoryEvent {
  static const int kSpendingHistoryKind = 7376;

  final CashuSpendDirection direction;
  final int amount;

  /// the tokens and their spend markers
  final List<({String tokenId, CashuSpendMarker marker})> tokens;

  final String? nutzapTokenId;

  CashuSpendingHistoryEvent({
    required this.direction,
    required this.amount,
    required this.tokens,
    this.nutzapTokenId,
  });
}
