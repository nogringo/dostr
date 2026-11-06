import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

bool _isSuccessStatus(int statusCode) => statusCode >= 200 && statusCode < 300;

HttpRequestException _failure(String method, http.Response response, Uri url) =>
    HttpRequestException(
      method: method,
      statusCode: response.statusCode,
      body: response.body,
      url: url.toString(),
      headers: response.headers,
    );

/// how much of the body [HttpRequestException.toString] shows
const _bodyPreviewLength = 200;

/// Exception thrown when an HTTP request completes with a non-2xx status code.
class HttpRequestException implements Exception {
  final String method;
  final int statusCode;
  final String body;
  final String url;

  /// response headers, names in lowercase
  final Map<String, String> headers;

  const HttpRequestException({
    required this.method,
    required this.statusCode,
    required this.body,
    required this.url,
    this.headers = const {},
  });

  @override
  String toString() {
    final preview = body.length > _bodyPreviewLength
        ? '${body.substring(0, _bodyPreviewLength)}...'
        : body;
    return 'HttpRequestException: $method $url returned $statusCode'
        '${preview.isEmpty ? '' : ': $preview'}';
  }
}

/// Upload progress information
class UploadProgress {
  final int sentBytes;
  final int totalBytes;
  final bool isComplete;
  final http.Response? response;

  UploadProgress({
    required this.sentBytes,
    required this.totalBytes,
    this.isComplete = false,
    this.response,
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

/// Aborts a request when called, or once [timeout] passes after the last
/// [startTimer].
class _Abort {
  final Uri url;
  final Duration? timeout;
  final _trigger = Completer<void>();
  Timer? _timer;
  var _timedOut = false;
  var _finished = false;

  _Abort(this.url, this.timeout);

  Future<void> get trigger => _trigger.future;

  void call() {
    _timer?.cancel();
    if (!_trigger.isCompleted) _trigger.complete();
  }

  void startTimer() {
    _timer?.cancel();
    final timeout = this.timeout;
    if (timeout == null || _finished || _trigger.isCompleted) return;
    _timer = Timer(timeout, () {
      _timedOut = true;
      call();
    });
  }

  void stopTimer() => _timer?.cancel();

  void finish() {
    _finished = true;
    _timer?.cancel();
  }

  /// the error to report: an abort the timer caused is a timeout
  Object reason(Object error) =>
      _timedOut && error is http.RequestAbortedException
      ? TimeoutException('$url', timeout)
      : error;
}

/// Data source for making http requests. A non-2xx response throws an
/// [HttpRequestException]. A `timeout` bounds the whole request and an
/// `idleTimeout` the time without data moving: either one ends the request
/// with a [TimeoutException].
class HttpRequestDS {
  final http.Client _client;
  final Set<_Abort> _pending = {};

  /// create new instance of HttpRequestDS
  HttpRequestDS(this._client);

  /// aborts every request still in flight. The client stays open: the app may
  /// share it through `http.runWithClient`
  void abortPending() {
    for (final abort in _pending) {
      abort();
    }
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? body,
    bool followRedirects = true,
    Duration? timeout,
  }) async {
    final abort = _Abort(url, timeout);
    final request =
        http.AbortableRequest(method, url, abortTrigger: abort.trigger)
          ..followRedirects = followRedirects
          ..headers.addAll(headers);
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

    _pending.add(abort);
    abort.startTimer();
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (!_isSuccessStatus(response.statusCode)) {
        throw _failure(method, response, url);
      }
      return response;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(abort.reason(error), stackTrace);
    } finally {
      abort.finish();
      _pending.remove(abort);
    }
  }

  /// make a get request to the given url and decode its JSON body. The url is
  /// used as given: the caller picks the scheme
  Future<Map<String, dynamic>> jsonRequest(
    Uri url, {
    bool followRedirects = true,
    Duration? timeout,
    Map<String, String> headers = const {"Accept": "application/json"},
  }) async {
    final response = await _send(
      'GET',
      url,
      headers: headers,
      followRedirects: followRedirects,
      timeout: timeout,
    );
    // JSON is UTF-8 (RFC 8259); `body` would fall back to latin1 for media
    // types such as application/nostr+json that carry no charset.
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// [body] is a `String`, a `List<int>` or a `Map<String, String>` sent as
  /// form fields
  Future<http.Response> put({
    required Uri url,
    required Object body,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send('PUT', url, headers: headers, body: body, timeout: timeout);

  /// Uploads [body] without loading it into memory: the body is read as the
  /// connection sends it. The upload starts on listen, and cancelling the
  /// subscription aborts it. The last [UploadProgress] carries the response.
  Stream<UploadProgress> putStream({
    required Uri url,
    required Stream<List<int>> body,
    Map<String, String> headers = const {},
    int? contentLength,
    Duration? idleTimeout,
  }) {
    final abort = _Abort(url, idleTimeout);
    final totalBytes = contentLength ?? 0;
    late final StreamController<UploadProgress> progress;

    Future<void> upload() async {
      var sentBytes = 0;
      progress.add(UploadProgress(sentBytes: 0, totalBytes: totalBytes));
      _pending.add(abort);
      abort.startTimer();
      try {
        final request =
            _UploadRequest(
                url,
                body.map((chunk) {
                  abort.startTimer();
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
                abortTrigger: abort.trigger,
              )
              ..headers.addAll(headers)
              ..contentLength = contentLength;
        final response = await http.Response.fromStream(
          await _client.send(request),
        );
        if (!_isSuccessStatus(response.statusCode)) {
          throw _failure('PUT', response, url);
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
        progress.addError(abort.reason(error), stackTrace);
      } finally {
        abort.finish();
        _pending.remove(abort);
        unawaited(progress.close());
      }
    }

    progress = StreamController(onListen: upload, onCancel: abort.call);
    return progress.stream;
  }

  /// [body] is a `String`, a `List<int>` or a `Map<String, String>` sent as
  /// form fields
  Future<http.Response> post({
    required Uri url,
    required Object body,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send('POST', url, headers: headers, body: body, timeout: timeout);

  Future<http.Response> head({
    required Uri url,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send('HEAD', url, headers: headers, timeout: timeout);

  Future<http.Response> get({
    required Uri url,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send('GET', url, headers: headers, timeout: timeout);

  /// Downloads [url] without loading it into memory, at the pace the listener
  /// reads it. The download starts on listen, and cancelling the subscription
  /// aborts it. A paused subscription does not count toward [idleTimeout].
  Stream<List<int>> getStream({
    required Uri url,
    Map<String, String> headers = const {},
    Duration? idleTimeout,
  }) {
    final abort = _Abort(url, idleTimeout);
    late final StreamController<List<int>> download;

    Future<void> start() async {
      final request = http.AbortableRequest(
        'GET',
        url,
        abortTrigger: abort.trigger,
      )..headers.addAll(headers);
      _pending.add(abort);
      abort.startTimer();
      try {
        final response = await _client.send(request);
        if (!_isSuccessStatus(response.statusCode)) {
          // reading the body drains the connection and keeps the server's reason
          throw _failure('GET', await http.Response.fromStream(response), url);
        }
        abort.startTimer();
        await download.addStream(
          response.stream.transform(
            StreamTransformer.fromHandlers(
              handleData: (chunk, sink) {
                abort.startTimer();
                sink.add(chunk);
              },
              handleError: (error, stackTrace, sink) =>
                  sink.addError(abort.reason(error), stackTrace),
            ),
          ),
        );
      } catch (error, stackTrace) {
        download.addError(abort.reason(error), stackTrace);
      } finally {
        abort.finish();
        _pending.remove(abort);
        unawaited(download.close());
      }
    }

    download = StreamController(
      onListen: start,
      onPause: abort.stopTimer,
      onResume: abort.startTimer,
      onCancel: abort.call,
    );
    return download.stream;
  }

  Future<http.Response> delete({
    required Uri url,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send('DELETE', url, headers: headers, timeout: timeout);
}
