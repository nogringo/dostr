import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain_layer/entities/relay_info.dart';
import '../../domain_layer/repositories/relay_info_repo.dart';

/// A relay answered with a status that may pass: 408, 429 or 5xx.
class RelayInfoStatusException extends http.ClientException {
  final int statusCode;

  RelayInfoStatusException(this.statusCode, Uri uri)
    : super('GET $uri returned $statusCode', uri);
}

/// [RelayInfoRepo] that fetches the document over HTTP(S) on every call, with
/// no cache
class HttpRelayInfoRepo implements RelayInfoRepo {
  final http.Client _client;

  /// deadline covering connection setup and the entire response body, so a
  /// stalled relay does not retain an HTTP socket
  final Duration timeout;

  /// a larger document is read as none, so a relay cannot fill the memory
  final int maxBytes;

  HttpRelayInfoRepo(
    this._client, {
    this.timeout = const Duration(seconds: 5),
    this.maxBytes = 1024 * 1024,
  });

  /// Null for an error status, a body that is not a JSON object or one past
  /// [maxBytes]. A timeout, a network failure or a [RelayInfoStatusException]
  /// throw, since they may pass. A url that is not ws, wss, http or https
  /// throws an [ArgumentError]
  @override
  Future<RelayInfo?> getRelayInfo(String url) async {
    final documentUrl = _documentUrl(url);
    final abort = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    final request = http.AbortableRequest(
      'GET',
      documentUrl,
      abortTrigger: abort.future,
    )..headers['Accept'] = 'application/nostr+json';
    final int statusCode;
    final Uint8List? body;
    try {
      final response = await _client.send(request);
      statusCode = response.statusCode;
      body = await _readAtMost(response, abort);
    } on http.RequestAbortedException {
      if (timedOut) throw TimeoutException('$documentUrl', timeout);
      rethrow;
    } finally {
      timer.cancel();
    }

    if (_mayPass(statusCode)) {
      throw RelayInfoStatusException(statusCode, documentUrl);
    }
    if (statusCode < 200 || statusCode >= 300 || body == null) return null;
    try {
      // JSON is UTF-8 (RFC 8259), whatever charset application/nostr+json carries
      return switch (jsonDecode(utf8.decode(body))) {
        final Map<String, dynamic> json => RelayInfo.fromJson(json),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  /// null past [maxBytes], after aborting the request so the rest is never read
  Future<Uint8List?> _readAtMost(
    http.StreamedResponse response,
    Completer<void> abort,
  ) async {
    Uint8List? tooLarge() {
      if (!abort.isCompleted) abort.complete();
      return null;
    }

    if ((response.contentLength ?? 0) > maxBytes) return tooLarge();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) return tooLarge();
    }
    return bytes.takeBytes();
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

bool _mayPass(int statusCode) =>
    statusCode == 408 || statusCode == 429 || statusCode >= 500;
