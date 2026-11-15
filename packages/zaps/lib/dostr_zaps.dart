/// Nostr zaps (NIP-57): zap requests, LNURL-pay invoices and zap
/// receipts.
///
/// ```dart
/// final zaps = Zaps(
///   query: query,
///   subscribe: subscribe,
///   lnurl: Lnurl(transport: HttpLnurlTransport(http.Client())),
/// );
/// final receipts = await zaps.fetchZappedReceipts(pubkey: pubkey).toList();
/// ```
library;

export 'src/http_lnurl_transport.dart';
export 'src/invoice_response.dart';
export 'src/lnurl.dart';
export 'src/lnurl_response.dart';
export 'src/lnurl_transport.dart';
export 'src/zap_receipt.dart';
export 'src/zap_request.dart';
export 'src/zaps.dart';
