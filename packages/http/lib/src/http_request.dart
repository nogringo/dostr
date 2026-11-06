import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

bool _isSuccessStatus(int statusCode) => statusCode >= 200 && statusCode < 300;

HttpRequestException _failure(http.Response response, Uri url) =>
    HttpRequestException(
      statusCode: response.statusCode,
      body: response.body,
      url: url.toString(),
      headers: response.headers,
    );

void _abort(Completer<void> trigger) {
  if (!trigger.isCompleted) trigger.complete();
}

/// Exception thrown when an HTTP request completes with a non-2xx status code.
class HttpRequestException implements Exception {
  final int statusCode;
  final String body;
  final String url;

  /// response headers, names in lowercase
  final Map<String, String> headers;

  const HttpRequestException({
    required this.statusCode,
    required this.body,
    required this.url,
    this.headers = const {},
  });

  @override
  String toString() => "error fetching STATUS: $statusCode, $body, Link: $url";
}

/// Upload progress information
class UploadProgress {
  final int sentBytes;
  final int totalBytes;
  final bool isComplete;
  final http.Response? response;
  final Object? error;

  UploadProgress({
    required this.sentBytes,
    required this.totalBytes,
    this.isComplete = false,
    this.response,
    this.error,
  });

  double get progress => totalBytes > 0 ? sentBytes / totalBytes : 0;
  double get percentage => progress * 100;
}

/// A PUT whose body the client pulls itself, so the body is read only as fast
/// as the connection sends it.
class _UploadRequest extends http.BaseRequest with http.Abortable {
  final Stream<List<int>> _body;

  @override
  final Future<void>? abortTrigger;

  _UploadRequest(Uri url, this._body, {this.abortTrigger}) : super('PUT', url);

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}

/// Data source for making http requests
class HttpRequestDS {
  final http.Client _client;
  final Set<Completer<void>> _pendingAborts = {};

  /// create new instance of HttpRequestDS
  HttpRequestDS(this._client);

  /// aborts every request still in flight. The client stays open: the app may
  /// share it through `http.runWithClient`
  void abortPending() {
    _pendingAborts.forEach(_abort);
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    bool followRedirects = true,
    Duration? timeout,
  }) async {
    final trigger = Completer<void>();
    final request = http.AbortableRequest(
      method,
      url,
      abortTrigger: trigger.future,
    )..followRedirects = followRedirects;
    if (headers != null) request.headers.addAll(headers);
    switch (body) {
      case null:
        break;
      case final String text:
        request.body = text;
      case final List<dynamic> bytes:
        request.bodyBytes = bytes.cast<int>();
      case final Map<dynamic, dynamic> fields:
        request.bodyFields = fields.cast<String, String>();
      default:
        throw ArgumentError.value(
          body,
          'body',
          'must be a String, a List<int> or a Map<String, String>',
        );
    }

    final timer = timeout == null
        ? null
        : Timer(timeout, () => _abort(trigger));
    _pendingAborts.add(trigger);
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (!_isSuccessStatus(response.statusCode)) {
        throw _failure(response, url);
      }
      return response;
    } finally {
      timer?.cancel();
      _pendingAborts.remove(trigger);
    }
  }

  /// make a get request to the given url and decode its JSON body. The url is
  /// used as given: the caller picks the scheme
  Future<Map<String, dynamic>> jsonRequest(
    String url, {
    bool followRedirects = true,
    Duration? timeout,
    Map<String, String> headers = const {"Accept": "application/json"},
  }) async {
    final response = await _send(
      'GET',
      Uri.parse(url),
      headers: headers,
      followRedirects: followRedirects,
      timeout: timeout,
    );
    // JSON is UTF-8 (RFC 8259); `body` would fall back to latin1 for media
    // types such as application/nostr+json that carry no charset.
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<http.Response> put({
    required Uri url,
    required Object body,
    required headers,
  }) => _send('PUT', url, headers: headers, body: body);

  /// Uploads [body] without loading it into memory: the body is read as the
  /// connection sends it. The upload starts on listen, and cancelling the
  /// subscription aborts it. The last [UploadProgress] carries the response.
  Stream<UploadProgress> putStream({
    required Uri url,
    required Stream<List<int>> body,
    required Map<String, String> headers,
    int? contentLength,
  }) {
    final trigger = Completer<void>();
    final totalBytes = contentLength ?? 0;
    late final StreamController<UploadProgress> progress;

    Future<void> upload() async {
      var sentBytes = 0;
      progress.add(UploadProgress(sentBytes: 0, totalBytes: totalBytes));
      _pendingAborts.add(trigger);
      try {
        final request =
            _UploadRequest(
                url,
                body.map((chunk) {
                  sentBytes += chunk.length;
                  // a client may still pull the body after an early response
                  if (!progress.isClosed) {
                    progress.add(
                      UploadProgress(
                        sentBytes: sentBytes,
                        totalBytes: totalBytes,
                      ),
                    );
                  }
                  return chunk;
                }),
                abortTrigger: trigger.future,
              )
              ..headers.addAll(headers)
              ..contentLength = contentLength;
        final response = await http.Response.fromStream(
          await _client.send(request),
        );
        if (!_isSuccessStatus(response.statusCode)) {
          throw _failure(response, url);
        }
        progress.add(
          UploadProgress(
            sentBytes: sentBytes,
            totalBytes: totalBytes,
            isComplete: true,
            response: response,
          ),
        );
      } catch (error, stackTrace) {
        progress.addError(error, stackTrace);
      } finally {
        _pendingAborts.remove(trigger);
        unawaited(progress.close());
      }
    }

    progress = StreamController(
      onListen: upload,
      onCancel: () => _abort(trigger),
    );
    return progress.stream;
  }

  Future<http.Response> post({
    required Uri url,

    /// String, Uint8List
    required Object body,
    required headers,
  }) => _send('POST', url, headers: headers, body: body);

  Future<http.Response> head({required Uri url, headers}) =>
      _send('HEAD', url, headers: headers);

  Future<http.Response> get({required Uri url, headers}) =>
      _send('GET', url, headers: headers);

  /// Get data as a stream to avoid loading entire file into memory
  /// Returns a stream of bytes that can be written directly to a file
  Stream<List<int>> getStream({
    required Uri url,
    Map<String, String>? headers,
  }) async* {
    final trigger = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: trigger.future,
    );
    if (headers != null) request.headers.addAll(headers);

    _pendingAborts.add(trigger);
    try {
      final streamedResponse = await _client.send(request);
      if (!_isSuccessStatus(streamedResponse.statusCode)) {
        // reading the body drains the connection and keeps the server's reason
        throw _failure(await http.Response.fromStream(streamedResponse), url);
      }
      yield* streamedResponse.stream;
    } finally {
      _pendingAborts.remove(trigger);
    }
  }

  Future<http.Response> delete({required Uri url, required headers}) =>
      _send('DELETE', url, headers: headers);
}
