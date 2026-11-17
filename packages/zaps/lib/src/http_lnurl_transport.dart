import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lnurl_response.dart';
import 'lnurl_transport.dart';
import 'logger.dart';

/// implementation of the [LnurlTransport] interface with http
class HttpLnurlTransport implements LnurlTransport {
  final http.Client client;

  /// constructor
  HttpLnurlTransport(this.client);

  @override
  Future<LnurlResponse?> requestLnurlResponse(String lnurl) async {
    try {
      return LnurlResponse.fromJson(await _getJson(lnurl));
    } catch (e) {
      logger.warning(() => e);
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchInvoice(String callbacklink) async {
    try {
      return await _getJson(callbacklink);
    } catch (e) {
      logger.fine(() => e);
      return null;
    }
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final uri = Uri.parse(url).replace(scheme: 'https');
    final response = await client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'GET $uri returned ${response.statusCode}',
        uri,
      );
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) {
      throw FormatException('$uri did not return a JSON object');
    }
    return json;
  }
}
