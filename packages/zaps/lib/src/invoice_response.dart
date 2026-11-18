/// An invoice that a LNURL-pay server issued.
final class InvoiceResponse {
  /// the BOLT11 invoice to pay
  final String invoice;

  /// the amount asked for, in sats
  final int amountSats;

  /// the pubkey that signs the zap receipt, when the server allows Nostr
  final String? nostrPubkey;

  const InvoiceResponse({
    required this.invoice,
    required this.amountSats,
    this.nostrPubkey,
  });
}
