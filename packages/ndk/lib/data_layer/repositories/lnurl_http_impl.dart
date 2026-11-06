import 'package:ndk/domain_layer/repositories/lnurl_transport.dart';
import 'package:ndk/domain_layer/usecases/lnurl/lnurl_response.dart';

import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_http/ndk_http.dart';

/// implementation of the [LnurlTransport] interface with http
class LnurlTransportHttpImpl implements LnurlTransport {
  final HttpRequestDS httpDS;

  /// constructor
  LnurlTransportHttpImpl(this.httpDS);

  @override
  Future<LnurlResponse?> requestLnurlResponse(String lnurl) async {
    try {
      final response = await httpDS.jsonRequest(url: _https(lnurl));
      return LnurlResponse.fromJson(response);
    } catch (e) {
      Logger.log.w(() => e);
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchInvoice(String callbacklink) async {
    try {
      return await httpDS.jsonRequest(url: _https(callbacklink));
    } catch (e) {
      Logger.log.d(() => e);
      return null;
    }
  }
}

Uri _https(String url) => Uri.parse(url).replace(scheme: 'https');
