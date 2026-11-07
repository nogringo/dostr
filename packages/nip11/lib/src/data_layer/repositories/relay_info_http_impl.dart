import '../../domain_layer/entities/relay_info.dart';
import '../../domain_layer/repositories/relay_info_repo.dart';
import 'package:ndk_http/ndk_http.dart';

/// implementation of the [RelayInfoRepo] interface with http
class RelayInfoHttpRepoImpl implements RelayInfoRepo {
  final NdkHttp httpDS;

  /// deadline covering connection setup and the entire response body, so a
  /// stalled relay does not retain an HTTP socket
  final Duration timeout;

  /// creates a new [RelayInfoHttpRepoImpl] instance
  RelayInfoHttpRepoImpl({
    required this.httpDS,
    this.timeout = const Duration(seconds: 5),
  });

  @override
  Future<RelayInfo?> getRelayInfo(String url) async {
    try {
      final json = await httpDS.jsonRequest(
        url: _documentUrl(url),
        timeout: timeout,
        headers: const {'Accept': 'application/nostr+json'},
      );
      return RelayInfo.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

/// NIP-11: the document is served over HTTP(S) on the relay's own url
Uri _documentUrl(String relayUrl) {
  final uri = Uri.parse(relayUrl);
  return switch (uri.scheme) {
    'ws' => uri.replace(scheme: 'http'),
    'wss' => uri.replace(scheme: 'https'),
    _ => uri,
  };
}
