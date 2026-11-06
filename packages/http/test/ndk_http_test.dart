import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:test/test.dart';

/// Never answers, like a stalled server, until the request is aborted.
MockClient _stalledClient(void Function(http.BaseRequest request) onAbort) =>
    MockClient.streaming((request, _) async {
      await (request as http.Abortable).abortTrigger!;
      onAbort(request);
      throw http.RequestAbortedException(request.url);
    });

MockClient _drainingClient() => MockClient.streaming((_, body) async {
  await body.drain<void>();
  return http.StreamedResponse(const Stream.empty(), 200);
});

/// Answers 200 with [body], which fails once the request is aborted, as
/// IOClient's does.
MockClient _bodyClient(StreamController<List<int>> body) =>
    MockClient.streaming((request, _) async {
      (request as http.Abortable).abortTrigger!.whenComplete(() {
        if (body.isClosed) return;
        body.addError(http.RequestAbortedException(request.url));
        body.close();
      });
      return http.StreamedResponse(body.stream, 200);
    });

/// Keeps the request as sent, which MockClient rebuilds.
class _RecordingClient extends http.BaseClient {
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}

class _RedirectedResponse extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  @override
  final Uri url;

  _RedirectedResponse(this.url) : super(Stream.value([1]), 200);
}

/// Answers like a client that followed a redirect to [to].
class _RedirectingClient extends http.BaseClient {
  final Uri to;

  _RedirectingClient(this.to);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _RedirectedResponse(to);
}

void main() {
  final url = Uri.parse('https://example.com/upload');

  test('jsonRequest decodes the body as UTF-8 and keeps the scheme', () async {
    late Uri requested;
    final ds = NdkHttp(
      MockClient((request) async {
        requested = request.url;
        return http.Response.bytes(utf8.encode('{"name":"café"}'), 200);
      }),
    );

    final json = await ds.jsonRequest(
      url: Uri.parse('http://localhost:7777/x'),
    );

    expect(json, {'name': 'café'});
    expect(requested.scheme, 'http');
  });

  test('jsonRequest throws FormatException unless the body is an object', () {
    final ds = NdkHttp(MockClient((_) async => http.Response('["bob"]', 200)));

    expect(ds.jsonRequest(url: url), throwsFormatException);
  });

  test(
    'jsonRequest headers add to its Accept, which they can replace',
    () async {
      final sent = <Map<String, String>>[];
      final ds = NdkHttp(
        MockClient((request) async {
          sent.add(request.headers);
          return http.Response('{}', 200);
        }),
      );

      await ds.jsonRequest(
        url: url,
        headers: const {'Authorization': 'Nostr x'},
      );
      await ds.jsonRequest(
        url: url,
        headers: const {'accept': 'application/nostr+json'},
      );

      expect(sent[0]['accept'], 'application/json');
      expect(sent[0]['authorization'], 'Nostr x');
      expect(sent[1]['accept'], 'application/nostr+json');
    },
  );

  test('a non-2xx response throws HttpRequestException', () async {
    final blob = Uri.parse('https://example.com/blob');
    final ds = NdkHttp(
      MockClient(
        (_) async =>
            http.Response('nope', 401, headers: {'x-reason': 'auth required'}),
      ),
    );

    expect(
      ds.get(url: blob),
      throwsA(
        isA<HttpRequestException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.uri, 'uri', blob)
            .having((e) => e.headers['x-reason'], 'x-reason', 'auth required'),
      ),
    );
  });

  test('an error body that breaks its charset keeps the status', () {
    final ds = NdkHttp(
      MockClient(
        (_) async => http.Response.bytes(
          [0xff, ...utf8.encode('quota')],
          507,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        ),
      ),
    );

    expect(
      ds.get(url: url),
      throwsA(
        isA<HttpRequestException>()
            .having((e) => e.statusCode, 'statusCode', 507)
            .having((e) => e.body, 'body', endsWith('quota')),
      ),
    );
  });

  test('getStream gives the status and headers before the body', () async {
    final body = StreamController<List<int>>();
    final ds = NdkHttp(
      MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          body.stream,
          200,
          contentLength: 3,
          headers: {'content-type': 'image/png'},
        ),
      ),
    );

    final response = await ds.getStream(url: url);

    expect(response.statusCode, 200);
    expect(response.contentLength, 3);
    expect(response.headers['content-type'], 'image/png');
    body
      ..add([1, 2, 3])
      ..close();
    expect(await response.stream.toBytes(), [1, 2, 3]);
  });

  test('getStream keeps the url a redirect led to', () async {
    final cdn = Uri.parse('https://cdn.example.com/blob');
    final response = await NdkHttp(_RedirectingClient(cdn)).getStream(url: url);

    expect(response, isA<http.BaseResponseWithUrl>());
    expect((response as http.BaseResponseWithUrl).url, cdn);
    expect(await response.stream.toBytes(), [1]);
  });

  test('getStream keeps the body of a non-2xx response', () async {
    final ds = NdkHttp(
      MockClient((_) async => http.Response('blob not found', 404)),
    );

    expect(
      ds.getStream(url: Uri.parse('https://example.com/blob')),
      throwsA(
        isA<HttpRequestException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.body, 'body', 'blob not found'),
      ),
    );
  });

  test('getStream restarts its idle timeout on an error response', () async {
    final ds = NdkHttp(
      MockClient.streaming((request, _) async {
        final body = StreamController<List<int>>();
        (request as http.Abortable).abortTrigger!.whenComplete(() {
          if (body.isClosed) return;
          body.addError(http.RequestAbortedException(request.url));
          body.close();
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          if (body.isClosed) return;
          body
            ..add(utf8.encode('blob not found'))
            ..close();
        });
        return http.StreamedResponse(body.stream, 404);
      }),
    );

    expect(
      ds.getStream(url: url, idleTimeout: const Duration(milliseconds: 150)),
      throwsA(
        isA<HttpRequestException>().having(
          (e) => e.body,
          'body',
          'blob not found',
        ),
      ),
    );
  });

  test('putStream reports the bytes sent, then the response', () async {
    final ds = NdkHttp(
      MockClient.streaming((request, body) async {
        final received = await body.toBytes();
        return http.StreamedResponse(
          Stream.value(utf8.encode('${received.length}')),
          200,
        );
      }),
    );

    final progress = await ds
        .putStream(
          url: url,
          body: Stream.fromIterable([
            [1, 2],
            [3],
          ]),
          headers: const {},
          contentLength: 3,
        )
        .toList();

    expect(progress.map((p) => p.sentBytes), [0, 2, 3, 3]);
    expect(progress.last.isComplete, isTrue);
    expect(progress.last.response!.body, '3');
  });

  test('putStream reads the body only as the client sends it', () async {
    var pulled = 0;
    Stream<List<int>> source() async* {
      for (var i = 0; i < 10; i++) {
        pulled++;
        yield [i];
      }
    }

    late int pulledBeforeSending;
    final ds = NdkHttp(
      MockClient.streaming((_, body) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        pulledBeforeSending = pulled;
        await body.drain<void>();
        return http.StreamedResponse(const Stream.empty(), 200);
      }),
    );

    await ds
        .putStream(url: url, body: source(), headers: const {})
        .drain<void>();

    expect(pulledBeforeSending, 0);
    expect(pulled, 10);
  });

  test('putStream keeps the bytes sent without a content length', () async {
    final progress = await NdkHttp(_drainingClient())
        .putStream(url: url, body: Stream.value([1, 2, 3]), headers: const {})
        .toList();

    expect(progress.last.isComplete, isTrue);
    expect(progress.last.sentBytes, 3);
    expect(progress.last.totalBytes, isNull);
    expect(progress.last.progress, isNull);
  });

  test('putStream reports a body error once', () async {
    final errors = [];
    await NdkHttp(_drainingClient())
        .putStream(
          url: url,
          body: Stream.error(StateError('disk')),
          headers: const {},
        )
        .handleError(errors.add)
        .drain<void>();

    expect(errors, [isA<StateError>()]);
  });

  test('putStream reports a non-2xx response as an error', () {
    final ds = NdkHttp(
      MockClient.streaming((_, body) async {
        await body.drain<void>();
        return http.StreamedResponse(Stream.value(utf8.encode('too big')), 413);
      }),
    );

    expect(
      ds.putStream(url: url, body: Stream.value([1])).last,
      throwsA(
        isA<HttpRequestException>()
            .having((e) => e.method, 'method', 'PUT')
            .having((e) => e.statusCode, 'statusCode', 413)
            .having((e) => e.body, 'body', 'too big'),
      ),
    );
  });

  test('an early error response aborts the upload at once', () async {
    final aborted = Completer<void>();
    final ds = NdkHttp(
      MockClient.streaming((request, _) async {
        (request as http.Abortable).abortTrigger!.whenComplete(
          aborted.complete,
        );
        return http.StreamedResponse(Stream.value(utf8.encode('too big')), 413);
      }),
    );

    final subscription = ds
        .putStream(url: url, body: Stream.value([1]))
        .listen(null, onError: (_) {});
    subscription.pause();

    await aborted.future.timeout(const Duration(seconds: 1));
    await subscription.cancel();
  });

  test('postStream sends a multipart form that http encodes', () async {
    late String method;
    late String contentType;
    late String received;
    final ds = NdkHttp(
      MockClient.streaming((request, body) async {
        method = request.method;
        contentType = request.headers['content-type']!;
        received = utf8.decode(await body.toBytes());
        return http.StreamedResponse(const Stream.empty(), 201);
      }),
    );
    final form = http.MultipartRequest('POST', url)
      ..files.add(
        http.MultipartFile(
          'file',
          Stream.value(utf8.encode('cat')),
          3,
          filename: 'cat.txt',
        ),
      );
    final body = form.finalize();

    final progress = await ds
        .postStream(
          url: url,
          body: body,
          headers: form.headers,
          contentLength: form.contentLength,
        )
        .toList();

    expect(method, 'POST');
    expect(contentType, startsWith('multipart/form-data; boundary='));
    expect(received, contains('filename="cat.txt"'));
    expect(progress.last.isComplete, isTrue);
    expect(progress.last.sentBytes, form.contentLength);
  });

  test('idleTimeout does not cap an upload that keeps moving', () async {
    final progress = await NdkHttp(_drainingClient())
        .putStream(
          url: url,
          body: Stream.periodic(
            const Duration(milliseconds: 10),
            (i) => [i],
          ).take(15),
          idleTimeout: const Duration(milliseconds: 100),
        )
        .toList();

    expect(progress.last.isComplete, isTrue);
    expect(progress.last.sentBytes, 15);
  });

  test('cancelling putStream aborts the upload', () async {
    final aborted = Completer<void>();
    final ds = NdkHttp(_stalledClient((_) => aborted.complete()));

    final subscription = ds
        .putStream(url: url, body: Stream.value([1]), headers: const {})
        .listen(null);
    await subscription.cancel();

    await aborted.future.timeout(const Duration(seconds: 1));
  });

  test('abortTrigger aborts getStream before the response', () async {
    final aborted = Completer<void>();
    final cancel = Completer<void>();
    final ds = NdkHttp(_stalledClient((_) => aborted.complete()));

    final download = ds.getStream(url: url, abortTrigger: cancel.future);
    cancel.complete();

    await expectLater(download, throwsA(isA<http.RequestAbortedException>()));
    await aborted.future.timeout(const Duration(seconds: 1));
  });

  test('cancelling the getStream body aborts the download', () async {
    final aborted = Completer<void>();
    final ds = NdkHttp(
      MockClient.streaming((request, _) async {
        (request as http.Abortable).abortTrigger!.whenComplete(
          aborted.complete,
        );
        return http.StreamedResponse(StreamController<List<int>>().stream, 200);
      }),
    );

    final response = await ds.getStream(url: url);
    await response.stream.listen(null).cancel();

    await aborted.future.timeout(const Duration(seconds: 1));
  });

  test('a timeout throws TimeoutException, not an abort', () async {
    final ds = NdkHttp(_stalledClient((_) {}));
    const timeout = Duration(milliseconds: 20);

    await Future.wait([
      for (final request in [
        ds.jsonRequest(url: url, timeout: timeout),
        ds.get(url: url, timeout: timeout),
        ds.post(url: url, body: 'x', timeout: timeout),
        ds.getStream(url: url, idleTimeout: timeout),
        ds
            .putStream(url: url, body: Stream.value([1]), idleTimeout: timeout)
            .toList(),
      ])
        expectLater(request, throwsA(isA<TimeoutException>())),
    ]);
  });

  test('getStream times out when the body stalls', () async {
    final ds = NdkHttp(_bodyClient(StreamController()..add([1])));

    final response = await ds.getStream(
      url: url,
      idleTimeout: const Duration(milliseconds: 20),
    );
    final received = <List<int>>[];
    final failed = Completer<Object>();
    response.stream.listen(received.add, onError: failed.complete);

    expect(await failed.future, isA<TimeoutException>());
    expect(received, [
      [1],
    ]);
  });

  test('a getStream body nobody listens to times out', () async {
    final ds = NdkHttp(_bodyClient(StreamController()));

    final response = await ds.getStream(
      url: url,
      idleTimeout: const Duration(milliseconds: 20),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(response.stream.toList(), throwsA(isA<TimeoutException>()));
  });

  test('idleTimeout does not cap a download that keeps moving', () async {
    final ds = NdkHttp(
      MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.periodic(
            const Duration(milliseconds: 10),
            (i) => [i],
          ).take(15),
          200,
        ),
      ),
    );

    final response = await ds.getStream(
      url: url,
      idleTimeout: const Duration(milliseconds: 100),
    );

    expect(await response.stream.toList(), hasLength(15));
  });

  test('a paused getStream body does not time out', () async {
    final body = StreamController<List<int>>();
    final ds = NdkHttp(_bodyClient(body));

    final response = await ds.getStream(
      url: url,
      idleTimeout: const Duration(milliseconds: 20),
    );
    final received = <List<int>>[];
    final done = Completer<void>();
    final subscription = response.stream.listen(
      received.add,
      onError: done.completeError,
      onDone: done.complete,
    );
    subscription.pause();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    subscription.resume();
    body
      ..add([1])
      ..close();

    await done.future;
    expect(received, [
      [1],
    ]);
  });

  test('a byte body is sent as given', () async {
    final client = _RecordingClient();
    final ds = NdkHttp(client);
    final bytes = Uint8List.fromList([1, 2, 3]);

    await ds.put(url: url, body: bytes);
    await ds.post(url: url, body: <dynamic>[4, 5]);

    expect(client.requests[0].bodyBytes, same(bytes));
    expect(client.requests[1].bodyBytes, [4, 5]);
  });

  test('a map body is sent as form fields', () async {
    final sent = <Map<String, String>>[];
    final ds = NdkHttp(
      MockClient((request) async {
        sent.add(request.bodyFields);
        return http.Response('', 200);
      }),
    );

    await ds.post(url: url, body: {'name': 'bob smith'});
    await ds.post(url: url, body: <dynamic, dynamic>{'name': 'alice'});

    expect(sent, [
      {'name': 'bob smith'},
      {'name': 'alice'},
    ]);
  });

  test('a body of another type throws ArgumentError', () async {
    final ds = NdkHttp(_drainingClient());

    for (final body in [
      42,
      {'count': 1},
      <dynamic>[1, 'x'],
    ]) {
      await expectLater(ds.post(url: url, body: body), throwsArgumentError);
    }
  });

  test('head and delete send their method', () async {
    final methods = <String>[];
    final ds = NdkHttp(
      MockClient((request) async {
        methods.add(request.method);
        return http.Response('', 200);
      }),
    );

    await ds.head(url: url);
    await ds.delete(url: url);

    expect(methods, ['HEAD', 'DELETE']);
  });

  test('a redirect not followed throws its 3xx', () async {
    final followed = <bool>[];
    final ds = NdkHttp(
      MockClient((request) async {
        followed.add(request.followRedirects);
        return http.Response('', 302);
      }),
    );

    await Future.wait([
      for (final request in [
        ds.jsonRequest(url: url, followRedirects: false),
        ds.get(url: url, followRedirects: false),
        ds.head(url: url, followRedirects: false),
        ds.getStream(url: url, followRedirects: false),
      ])
        expectLater(
          request,
          throwsA(
            isA<HttpRequestException>().having(
              (e) => e.statusCode,
              'statusCode',
              302,
            ),
          ),
        ),
    ]);
    expect(followed, [false, false, false, false]);
  });

  test('HttpRequestException names the request and shortens the body', () {
    final error = HttpRequestException(
      method: 'GET',
      statusCode: 500,
      body: 'x' * 10000,
      uri: Uri.parse('https://example.com/blob'),
    );

    expect(
      error.toString(),
      startsWith(
        'HttpRequestException: GET https://example.com/blob returned 500: xxx',
      ),
    );
    expect(error.toString().length, lessThan(300));
  });

  test('abortPending aborts every request in flight', () async {
    final aborted = <String>[];
    final ds = NdkHttp(
      _stalledClient((request) => aborted.add(request.method)),
    );

    final requests = [
      ds.jsonRequest(url: url),
      ds.get(url: url),
      ds.post(url: url, body: 'x', headers: const <String, String>{}),
      ds.getStream(url: url),
      ds
          .putStream(url: url, body: Stream.value([1]), headers: const {})
          .toList(),
    ];
    await Future<void>.delayed(Duration.zero);
    ds.abortPending();

    for (final request in requests) {
      await expectLater(request, throwsA(isA<http.RequestAbortedException>()));
    }
    expect(aborted, unorderedEquals(['GET', 'GET', 'POST', 'GET', 'PUT']));
  });
}
