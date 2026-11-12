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

class UploadProgress {
  final int sentBytes;
  final int totalBytes;
  final bool isComplete;
  final http.Response? response;

  const UploadProgress({
    required this.sentBytes,
    required this.totalBytes,
    this.isComplete = false,
    this.response,
  });

  double get progress => totalBytes > 0 ? sentBytes / totalBytes : 0;
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

/// Turns a non-2xx response into an [HttpRequestException], streams uploads
/// and downloads, and aborts every request in flight on [abortPending].
class BlossomHttp {
  final http.Client _client;
  final Set<Completer<void>> _pending = {};

  BlossomHttp(this._client);

  /// aborts every request still in flight. The client stays open: the app may
  /// share it through `http.runWithClient`
  void abortPending() {
    for (final abort in _pending.toList()) {
      _abort(abort);
    }
  }

  static void _abort(Completer<void> abort) {
    if (!abort.isCompleted) abort.complete();
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      url,
      abortTrigger: abort.future,
    )..headers.addAll(headers);
    if (body != null) request.body = body;

    _pending.add(abort);
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (!_isSuccessStatus(response.statusCode)) {
        throw _failure(method, response, url);
      }
      return response;
    } finally {
      _pending.remove(abort);
    }
  }

  Future<http.Response> put({
    required Uri url,
    required String body,
    Map<String, String> headers = const {},
  }) => _send('PUT', url, headers: headers, body: body);

  Future<http.Response> head({
    required Uri url,
    Map<String, String> headers = const {},
  }) => _send('HEAD', url, headers: headers);

  Future<http.Response> get({
    required Uri url,
    Map<String, String> headers = const {},
  }) => _send('GET', url, headers: headers);

  Future<http.Response> delete({
    required Uri url,
    Map<String, String> headers = const {},
  }) => _send('DELETE', url, headers: headers);

  /// Uploads [body] without loading it into memory: the body is read as the
  /// connection sends it. The upload starts on listen, and cancelling the
  /// subscription aborts it. The last [UploadProgress] carries the response.
  Stream<UploadProgress> putStream({
    required Uri url,
    required Stream<List<int>> body,
    required int contentLength,
    Map<String, String> headers = const {},
  }) {
    final abort = Completer<void>();
    late final StreamController<UploadProgress> progress;

    Future<void> upload() async {
      var sentBytes = 0;
      progress.add(UploadProgress(sentBytes: 0, totalBytes: contentLength));
      _pending.add(abort);
      try {
        final request =
            _UploadRequest(
                'PUT',
                url,
                body.map((chunk) {
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
                abortTrigger: abort.future,
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
            totalBytes: contentLength,
            isComplete: true,
            response: response,
          ),
        );
      } catch (error, stackTrace) {
        // stops a body still going out, without waiting for the listener
        _abort(abort);
        progress.addError(error, stackTrace);
      } finally {
        _pending.remove(abort);
        unawaited(progress.close());
      }
    }

    progress = StreamController(
      onListen: upload,
      onCancel: () => _abort(abort),
    );
    return progress.stream;
  }

  /// Downloads [url] without loading it into memory. The future completes with
  /// the status and headers, and the response's `stream` reads the body at the
  /// pace the listener reads it. Cancelling its subscription aborts the
  /// download.
  Future<http.StreamedResponse> getStream({
    required Uri url,
    Map<String, String> headers = const {},
  }) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort.future,
    )..headers.addAll(headers);

    _pending.add(abort);
    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
      if (!_isSuccessStatus(response.statusCode)) {
        // reading the body drains the connection and keeps the server's reason
        throw _failure('GET', await http.Response.fromStream(response), url);
      }
    } catch (_) {
      _pending.remove(abort);
      rethrow;
    }

    late final StreamController<List<int>> body;
    body = StreamController(
      onListen: () async {
        await body.addStream(response.stream);
        _pending.remove(abort);
        unawaited(body.close());
      },
      onCancel: () => _abort(abort),
    );
    return _StreamedResponse(body.stream, response);
  }
}
