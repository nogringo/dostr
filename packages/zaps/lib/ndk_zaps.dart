/// The zaps of NDK (NIP-57): zap requests, LNURL-pay invoices and zap
/// receipts.
///
/// ```dart
/// final zaps = Zaps(
///   query: query,
///   subscribe: subscribe,
///   lnurl: Lnurl(transport: LnurlTransportHttpImpl(NdkHttp(http.Client()))),
/// );
/// final receipts = await zaps.fetchZappedReceipts(pubKey: pubKey).toList();
/// ```
library;

export 'src/invoice_response.dart';
export 'src/lnurl.dart';
export 'src/lnurl_http_impl.dart';
export 'src/lnurl_response.dart';
export 'src/lnurl_transport.dart';
export 'src/zap_receipt.dart';
export 'src/zap_request.dart';
export 'src/zaps.dart';
