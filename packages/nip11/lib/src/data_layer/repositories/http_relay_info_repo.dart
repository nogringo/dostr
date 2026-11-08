import '../../domain_layer/entities/relay_info.dart';
import '../../domain_layer/repositories/relay_info_repo.dart';
import 'package:ndk_http/ndk_http.dart';

/// [RelayInfoRepo] that fetches the document over HTTP(S) on every call, with
/// no cache
class HttpRelayInfoRepo implements RelayInfoRepo {
  final NdkHttp _http;

  /// deadline covering connection setup and the entire response body, so a
  /// stalled relay does not retain an HTTP socket
  final Duration timeout;

  /// a larger document is read as none, so a relay cannot fill the memory
  final int maxBytes;

  HttpRelayInfoRepo(
    this._http, {
    this.timeout = const Duration(seconds: 5),
    this.maxBytes = 1024 * 1024,
  });

  /// Null for an error status, a body that is not a JSON object or one past
  /// [maxBytes]. A timeout, a network failure, a 408, a 429 or a 5xx throw,
  /// since they may pass. A url that is not ws, wss, http or https throws an
  /// [ArgumentError]
  @override
  Future<RelayInfo?> getRelayInfo(String url) async {
    final documentUrl = _documentUrl(url);
    try {
      final json = await _http.jsonRequest(
        url: documentUrl,
        timeout: timeout,
        maxBytes: maxBytes,
        headers: const {'Accept': 'application/nostr+json'},
      );
      return RelayInfo.fromJson(json);
    } on Exception catch (error) {
      if (_servesNoDocument(error)) return null;
      rethrow;
    }
  }
}

/// NIP-11: the document is served over HTTP(S) on the relay's own url
Uri _documentUrl(String relayUrl) => switch (Uri.tryParse(relayUrl)) {
  Uri(scheme: 'ws') && final uri => uri.replace(scheme: 'http'),
  Uri(scheme: 'wss') && final uri => uri.replace(scheme: 'https'),
  Uri(scheme: 'http' || 'https') && final uri => uri,
  _ => throw ArgumentError.value(
    relayUrl,
    'url',
    'is not a ws, wss, http or https url',
  ),
};

/// the relay answered, and asking again would get the same answer
bool _servesNoDocument(Exception error) => switch (error) {
  HttpRequestException(:final statusCode) ||
  HttpResponseTooLargeException(:final statusCode) => !_mayPass(statusCode),
  FormatException() => true,
  _ => false,
};

bool _mayPass(int statusCode) =>
    statusCode == 408 || statusCode == 429 || statusCode >= 500;
