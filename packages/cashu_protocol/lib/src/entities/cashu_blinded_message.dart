/// An output sent to the mint to sign, with its blinded secret `B_` (NUT-00).
class CashuBlindedMessage {
  CashuBlindedMessage({
    required this.id,
    required this.amount,
    required this.blindedMessage,
  });

  final String id;
  final int amount;

  /// B_
  final String blindedMessage;

  factory CashuBlindedMessage.fromServerMap(Map json) {
    return CashuBlindedMessage(
      id: json['id'],
      amount: json['amount'] is int
          ? json['amount']
          : int.tryParse(json['amount']) ?? 0,
      blindedMessage: json['B_'],
    );
  }

  Map<String, Object> toJson() {
    return {'id': id, 'amount': amount, 'B_': blindedMessage};
  }

  @override
  String toString() {
    return '${super.toString()}, id: $id, amount: $amount, blindedMessage: $blindedMessage';
  }
}

/// A [CashuBlindedMessage] with the secret and blinding factor [r] the wallet
/// keeps to unblind its signature.
class CashuBlindedMessageItem {
  final CashuBlindedMessage blindedMessage;
  final String secret;
  final BigInt r;
  final int amount;

  CashuBlindedMessageItem({
    required this.blindedMessage,
    required this.secret,
    required this.r,
    required this.amount,
  });
}
