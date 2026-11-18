import 'lnurl_response.dart';

/// Reaches the LNURL-pay servers for `Lnurl`.
abstract class LnurlTransport {
  /// What the LNURL-pay server at [lnurl] answers, or null when it cannot be
  /// reached or does not answer as one.
  Future<LnurlResponse?> requestLnurlResponse(String lnurl);

  /// The JSON object that [callbacklink] answers, or null when it cannot be
  /// reached.
  Future<Map<String, dynamic>?> fetchInvoice(String callbacklink);
}
