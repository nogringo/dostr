import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

bool _isSuccessStatus(int statusCode) => statusCode >= 200 && statusCode < 300;

HttpRequestException _failure(String method, http.Response response, Uri url) =>
    HttpRequestException(
      method: method,
      statusCode: response.statusCode,
      body: _bodyText(response),
      uri: url,
      headers: response.headers,
    );

/// a body whose bytes do not match its charset must not hide the error
String _bodyText(http.Response response) {
  try {
    return response.body;
  } on FormatException {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

/// how much of the body [HttpRequestException.toString] shows
const _bodyPreviewLength = 200;

/// Exception thrown when an HTTP request completes with a non-2xx status code.
/// It is a [http.ClientException], like the failure of a request that got no
/// response.
class HttpRequestException extends http.ClientException {
  final String method;
  final int statusCode;
  final String body;

  /// response headers, names in lowercase
  final Map<String, String> headers;

  HttpRequestException({
    required this.method,
    required this.statusCode,
    required this.body,
    required Uri uri,
    this.headers = const {},
  }) : super('$method $uri returned $statusCode', uri);

  @override
  Uri get uri => super.uri!;

  @override
  String toString() {
    final preview = body.length > _bodyPreviewLength
        ? '${body.substring(0, _bodyPreviewLength)}...'
        : body;
    return 'HttpRequestException: $message'
        '${preview.isEmpty ? '' : ': $preview'}';
  }
}

/// Upload progress information
class UploadProgress {
  final int sentBytes;

  /// null when the upload has no content length
  final int? totalBytes;
  final bool isComplete;
  final http.Response? response;

  const UploadProgress({
    required this.sentBytes,
    this.totalBytes,
    this.isComplete = false,
    this.response,
  });

  /// null when [totalBytes] is unknown
  double? get progress => switch (totalBytes) {
    null => null,
    final total when total > 0 => sentBytes / total,
    _ => 0,
  };

  double? get percentage => switch (progress) {
    final progress? => progress * 100,
    null => null,
  };
}

/// A request whose body the client pulls itself, so the body is read only as
/// fast as the connection sends it.
class _UploadRequest extends http.BaseRequest with http.Abortable {
  final Stream<List<int>> _body;

  @override
  final Future<void>? abortTrigger;

  _UploadRequest(super.method, super.url, this._body, {this.abortTrigger});

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}

/// [response] with [stream] for its body
class _StreamedResponse extends http.StreamedResponse {
  _StreamedResponse(Stream<List<int>> stream, http.StreamedResponse response)
    : super(
        stream,
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
}

/// keeps the url a redirect led to, as `BaseRequest.send` does in `http`
class _StreamedResponseWithUrl extends _StreamedResponse
    implements http.BaseResponseWithUrl {
  @override
  final Uri url;

  _StreamedResponseWithUrl(super.stream, super.response, this.url);
}

/// Aborts a request when called, or once [timeout] passes after the last
/// [startTimer]. A [pause] holds the timer until [resume].
class _Abort {
  final Uri url;
  final Duration? timeout;
  final _trigger = Completer<void>();
  Timer? _timer;
  var _timedOut = false;
  var _paused = false;
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
    if (timeout == null || _paused || _finished || _trigger.isCompleted) {
      return;
    }
    _timer = Timer(timeout, () {
      _timedOut = true;
      call();
    });
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
  }

  void resume() {
    _paused = false;
    startTimer();
  }

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
class NdkHttp {
  final http.Client _client;
  final Set<_Abort> _pending = {};

  /// create new instance of NdkHttp
  NdkHttp(this._client);

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
      // cast() would hide a Uint8List from http, which then copies it
      case final List<int> bytes:
        request.bodyBytes = bytes;
      // cast() is lazy: a wrong element would only fail inside http
      case final List<dynamic> bytes when bytes.every((byte) => byte is int):
        request.bodyBytes = bytes.cast<int>();
      case final Map<dynamic, dynamic> fields
          when fields.entries.every(
            (field) => field.key is String && field.value is String,
          ):
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

  Stream<UploadProgress> _sendStream(
    String method,
    Uri url, {
    required Stream<List<int>> body,
    required Map<String, String> headers,
    required int? contentLength,
    required Duration? idleTimeout,
  }) {
    final abort = _Abort(url, idleTimeout);
    late final StreamController<UploadProgress> progress;

    Future<void> upload() async {
      var sentBytes = 0;
      progress.add(UploadProgress(sentBytes: 0, totalBytes: contentLength));
      _pending.add(abort);
      abort.startTimer();
      try {
        final request =
            _UploadRequest(
                method,
                url,
                body.map((chunk) {
                  abort.startTimer();
                  sentBytes += chunk.length;
                  // a client may still pull the body after an early response
                  if (!progress.isClosed) {
                    progress.add(
                      UploadProgress(
                        sentBytes: sentBytes,
                        totalBytes: contentLength,
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
          throw _failure(method, response, url);
        }
        progress.add(
          UploadProgress(
            sentBytes: sentBytes,
            totalBytes: contentLength,
            isComplete: true,
            response: response,
          ),
        );
      } catch (error, stackTrace) {
        // stops a body still going out, without waiting for the listener
        abort();
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

  /// make a get request to the given url and decode its JSON body, which must
  /// be an object: anything else throws a [FormatException]. The url is used
  /// as given: the caller picks the scheme. [headers] add to
  /// `Accept: application/json`, which they can replace
  Future<Map<String, dynamic>> jsonRequest({
    required Uri url,
    bool followRedirects = true,
    Duration? timeout,
    Map<String, String> headers = const {},
  }) async {
    final response = await _send(
      'GET',
      url,
      // request headers ignore case, so the caller's accept replaces this one
      headers: {'Accept': 'application/json', ...headers},
      followRedirects: followRedirects,
      timeout: timeout,
    );
    // JSON is UTF-8 (RFC 8259); `body` would fall back to latin1 for media
    // types such as application/nostr+json that carry no charset.
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) {
      throw FormatException('$url did not return a JSON object');
    }
    return json;
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
  /// [idleTimeout] also runs while the server processes the body before it
  /// answers.
  Stream<UploadProgress> putStream({
    required Uri url,
    required Stream<List<int>> body,
    Map<String, String> headers = const {},
    int? contentLength,
    Duration? idleTimeout,
  }) => _sendStream(
    'PUT',
    url,
    body: body,
    headers: headers,
    contentLength: contentLength,
    idleTimeout: idleTimeout,
  );

  /// [body] is a `String`, a `List<int>` or a `Map<String, String>` sent as
  /// form fields
  Future<http.Response> post({
    required Uri url,
    required Object body,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send('POST', url, headers: headers, body: body, timeout: timeout);

  /// [putStream] with a POST, such as a multipart form that
  /// `http.MultipartRequest` encodes
  Stream<UploadProgress> postStream({
    required Uri url,
    required Stream<List<int>> body,
    Map<String, String> headers = const {},
    int? contentLength,
    Duration? idleTimeout,
  }) => _sendStream(
    'POST',
    url,
    body: body,
    headers: headers,
    contentLength: contentLength,
    idleTimeout: idleTimeout,
  );

  Future<http.Response> head({
    required Uri url,
    bool followRedirects = true,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send(
    'HEAD',
    url,
    headers: headers,
    followRedirects: followRedirects,
    timeout: timeout,
  );

  Future<http.Response> get({
    required Uri url,
    bool followRedirects = true,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send(
    'GET',
    url,
    headers: headers,
    followRedirects: followRedirects,
    timeout: timeout,
  );

  /// Downloads [url] without loading it into memory. The future completes with
  /// the status and headers, and the response's `stream` reads the body at the
  /// pace the listener reads it. Cancelling its subscription aborts the
  /// download, and completing [abortTrigger] aborts it at any point. A paused
  /// subscription does not count toward [idleTimeout], but a body nobody
  /// listens to yet does.
  Future<http.StreamedResponse> getStream({
    required Uri url,
    bool followRedirects = true,
    Map<String, String> headers = const {},
    Duration? idleTimeout,
    Future<void>? abortTrigger,
  }) async {
    final abort = _Abort(url, idleTimeout);
    abortTrigger?.whenComplete(abort.call).ignore();
    final request =
        http.AbortableRequest('GET', url, abortTrigger: abort.trigger)
          ..followRedirects = followRedirects
          ..headers.addAll(headers);
    void finish() {
      abort.finish();
      _pending.remove(abort);
    }

    _pending.add(abort);
    abort.startTimer();
    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
      abort.startTimer();
      if (!_isSuccessStatus(response.statusCode)) {
        // reading the body drains the connection and keeps the server's reason
        throw _failure('GET', await http.Response.fromStream(response), url);
      }
    } catch (error, stackTrace) {
      finish();
      Error.throwWithStackTrace(abort.reason(error), stackTrace);
    }

    late final StreamController<List<int>> body;
    body = StreamController(
      onListen: () async {
        await body.addStream(
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
        finish();
        unawaited(body.close());
      },
      onPause: abort.pause,
      onResume: abort.resume,
      onCancel: abort.call,
    );
    return switch (response) {
      http.BaseResponseWithUrl(url: final finalUrl) => _StreamedResponseWithUrl(
        body.stream,
        response,
        finalUrl,
      ),
      _ => _StreamedResponse(body.stream, response),
    };
  }

  Future<http.Response> delete({
    required Uri url,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _send('DELETE', url, headers: headers, timeout: timeout);
}
