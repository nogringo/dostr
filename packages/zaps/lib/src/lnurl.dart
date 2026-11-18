import 'invoice_response.dart';
import 'lnurl_response.dart';
import 'lnurl_transport.dart';
import 'logger.dart';
import 'zap_request.dart';

/// Talks to LNURL-pay servers (LUD-06) through [LnurlTransport].
class Lnurl {
  final LnurlTransport _transport;

  Lnurl({required LnurlTransport transport}) : _transport = transport;

  /// The LNURL-pay link of the lightning address [lud16] (LUD-16):
  /// `name@domain.com` is `https://domain.com/.well-known/lnurlp/name`.
  /// Null when [lud16] has no `@`.
  static String? getLud16LinkFromLud16(String lud16) {
    final parts = lud16.split('@');
    if (parts.length < 2) {
      return null;
    }
    return 'https://${parts[1]}/.well-known/lnurlp/${parts[0]}';
  }

  /// What the LNURL-pay server at [link] answers, or null when it cannot be
  /// reached or does not answer as one.
  Future<LnurlResponse?> getLnurlResponse(String link) =>
      _transport.requestLnurlResponse(link);

  /// The invoice of [amountSats] that the callback of [lnurlResponse] issues,
  /// or null when it gives none.
  ///
  /// It carries [zapRequest] when the server allows Nostr and [zapRequest] is
  /// signed, and [comment], cut to the length the server takes, when the
  /// server takes comments.
  Future<InvoiceResponse?> fetchInvoice({
    required LnurlResponse lnurlResponse,
    required int amountSats,
    ZapRequest? zapRequest,
    String? comment,
  }) async {
    var callback = lnurlResponse.callback;
    callback += callback.contains('?') ? '&' : '?';
    callback += 'amount=${amountSats * 1000}';

    final commentAllowed = lnurlResponse.commentAllowed;
    if (comment != null &&
        comment.trim().isNotEmpty &&
        commentAllowed != null) {
      if (commentAllowed < comment.length) {
        comment = comment.substring(0, commentAllowed);
      }
      callback += '&comment=${Uri.encodeQueryComponent(comment)}';
    }

    if (lnurlResponse.allowsNostr &&
        zapRequest != null &&
        zapRequest.sig != null &&
        zapRequest.sig!.isNotEmpty) {
      callback +=
          '&nostr=${Uri.encodeQueryComponent(zapRequest.toJsonString())}';
    }

    logger.fine(() => 'getInvoice callback $callback');

    try {
      final response = await _transport.fetchInvoice(callback);
      return InvoiceResponse(
        invoice: response!['pr'],
        amountSats: amountSats,
        nostrPubkey: lnurlResponse.nostrPubkey,
      );
    } catch (e) {
      logger.fine(() => e);
    }
    return null;
  }
}
