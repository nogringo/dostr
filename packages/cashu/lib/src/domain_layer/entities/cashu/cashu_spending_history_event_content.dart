import 'cashu_spending_history_event.dart';

class CashuSpendingHistoryEventContent {
  final CashuSpendDirection direction;
  final int amount;

  /// the tokens and their spend markers
  final List<({String tokenId, CashuSpendMarker marker})> tokens;

  CashuSpendingHistoryEventContent({
    required this.direction,
    required this.amount,
    required this.tokens,
  });

  /// extracts data from plain lists
  factory CashuSpendingHistoryEventContent.fromJson(
    List<List<String>> jsonList,
  ) {
    CashuSpendDirection? direction;
    int? amount;
    List<({String tokenId, CashuSpendMarker marker})> tokens = [];

    for (final item in jsonList) {
      if (item.isEmpty) continue;

      switch (item.first) {
        case 'direction':
          if (item.length > 1) {
            direction = CashuSpendDirection.fromValue(item[1]);
          }
          break;

        case 'amount':
          if (item.length > 1) {
            amount = int.tryParse(item[1]);
          }
          break;

        case 'e':
          if (item.length >= 4) {
            final tokenId = item[1];
            final markerString = item[3];

            CashuSpendMarker marker = CashuSpendMarker.fromValue(markerString);

            tokens.add((tokenId: tokenId, marker: marker));
          }
          break;
      }
    }
    if (direction == null) {
      throw Exception("err parsing direction");
    }

    if (amount == null) {
      throw Exception("err parsing amount");
    }

    return CashuSpendingHistoryEventContent(
      direction: direction,
      amount: amount,
      tokens: tokens,
    );
  }
}
