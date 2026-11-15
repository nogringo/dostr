import 'cashu_blinded_signature.dart';
import 'cashu_quote.dart';

/// The mint's reply to a melt (NUT-05), with the preimage once paid and the
/// NUT-08 change.
class CashuMeltResponse {
  final String qoteId;
  final String mintUrl;
  final CashuQuoteState state;
  final String? paymentPreimage;
  final List<CashuBlindedSignature> change;

  CashuMeltResponse({
    required this.qoteId,
    required this.mintUrl,
    required this.state,
    this.paymentPreimage,
    required this.change,
  });

  factory CashuMeltResponse.fromServerMap({
    required Map<String, dynamic> map,
    required String mintUrl,
    required String quoteId,
  }) {
    return CashuMeltResponse(
      qoteId: quoteId,
      mintUrl: mintUrl,
      state: CashuQuoteState.fromValue(map['state'] as String),
      paymentPreimage: map['payment_preimage'] as String?,
      change:
          (map['change'] as List<dynamic>?)
              ?.map(
                (e) => CashuBlindedSignature.fromServerMap(
                  e as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
    );
  }
}
