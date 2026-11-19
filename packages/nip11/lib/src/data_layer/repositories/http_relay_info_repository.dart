import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain_layer/entities/relay_info.dart';
import '../../domain_layer/repositories/relay_info_repository.dart';

/// A relay answered with a status that may pass: 408, 429 or 5xx.
class RelayInfoStatusException extends http.ClientException {
  final int statusCode;

  RelayInfoStatusException(this.statusCode, Uri uri)
    : super('GET $uri returned $statusCode', uri);
}

/// [RelayInfoRepository] that fetches the document over HTTP(S) on every call, with
/// no cache
class HttpRelayInfoRepository implements RelayInfoRepository {
  final http.Client _client;

  /// deadline covering connection setup and the entire response body, so a
  /// stalled relay does not retain an HTTP socket. It holds with a client that
  /// ignores `abortTrigger` too, which then keeps its socket
  final Duration timeout;

  /// a larger document is read as none, so a relay cannot fill the memory
  final int maxBytes;

  HttpRelayInfoRepository(
    this._client, {
    this.timeout = const Duration(seconds: 5),
    this.maxBytes = 1024 * 1024,
  });

  /// Null for an error status, a body that is not a JSON object, one past
  /// [maxBytes] or one nested more than 64 levels deep. A timeout, a network
  /// failure or a [RelayInfoStatusException] throw, since they may pass. A url
  /// that is not ws, wss, http or https throws an [ArgumentError]
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
      final response = await _send(request, abort.future);
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
    if (_nestsDeeper(body, _maxDepth)) return null;
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

  /// the response of [request], or a [http.RequestAbortedException] once
  /// [abort] completes, from a client that ignores it too
  Future<http.StreamedResponse> _send(
    http.BaseRequest request,
    Future<void> abort,
  ) {
    final response = Completer<http.StreamedResponse>();
    unawaited(
      _client
          .send(request)
          .then(
            (value) {
              if (response.isCompleted) {
                value.stream.listen(null).cancel().ignore();
              } else {
                response.complete(value);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!response.isCompleted) {
                response.completeError(error, stackTrace);
              }
            },
          ),
    );
    unawaited(
      abort.then((_) {
        if (!response.isCompleted) {
          response.completeError(http.RequestAbortedException(request.url));
        }
      }),
    );
    return response.future;
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
    // not an `await for`: on DDC, leaving one escapes the fake async zone of
    // testWidgets, so pump never ends the read
    final bytes = BytesBuilder(copy: false);
    final read = Completer<Uint8List?>();
    late final StreamSubscription<List<int>> subscription;
    subscription = response.stream.listen(
      (chunk) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          subscription.cancel().ignore();
          read.complete(tooLarge());
        }
      },
      onError: read.completeError,
      onDone: () => read.complete(bytes.takeBytes()),
      cancelOnError: true,
    );
    // a client that ignores the abort trigger never ends the stream
    unawaited(
      abort.future.then((_) {
        if (read.isCompleted) return;
        subscription.cancel().ignore();
        read.completeError(http.RequestAbortedException(response.request?.url));
      }),
    );
    return read.future;
  }
}

const _maxDepth = 64;

const _quote = 0x22;
const _backslash = 0x5C;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;

/// whether [json] nests arrays or objects more than [levels] deep, read on the
/// bytes since decoding them overflows the stack on the web
bool _nestsDeeper(Uint8List json, int levels) {
  var depth = 0;
  var inString = false;
  for (var i = 0; i < json.length; i++) {
    switch (json[i]) {
      case _backslash when inString:
        i++;
      case _quote:
        inString = !inString;
      case _openBracket || _openBrace when !inString:
        if (++depth > levels) return true;
      case _closeBracket || _closeBrace when !inString:
        depth--;
    }
  }
  return false;
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
