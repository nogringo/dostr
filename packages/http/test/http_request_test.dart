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

/// Keeps the request as sent, which MockClient rebuilds.
class _RecordingClient extends http.BaseClient {
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}

void main() {
  final url = Uri.parse('https://example.com/upload');

  test('jsonRequest decodes the body as UTF-8 and keeps the scheme', () async {
    late Uri requested;
    final ds = HttpRequestDS(
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
    final ds = HttpRequestDS(
      MockClient((_) async => http.Response('["bob"]', 200)),
    );

    expect(ds.jsonRequest(url: url), throwsFormatException);
  });

  test('a non-2xx response throws HttpRequestException', () async {
    final blob = Uri.parse('https://example.com/blob');
    final ds = HttpRequestDS(
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
    final ds = HttpRequestDS(
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

  test('getStream keeps the body of a non-2xx response', () async {
    final ds = HttpRequestDS(
      MockClient((_) async => http.Response('blob not found', 404)),
    );

    expect(
      ds.getStream(url: Uri.parse('https://example.com/blob')).toList(),
      throwsA(
        isA<HttpRequestException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.body, 'body', 'blob not found'),
      ),
    );
  });

  test('putStream reports the bytes sent, then the response', () async {
    final ds = HttpRequestDS(
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
    final ds = HttpRequestDS(
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
    final progress = await HttpRequestDS(_drainingClient())
        .putStream(url: url, body: Stream.value([1, 2, 3]), headers: const {})
        .toList();

    expect(progress.last.isComplete, isTrue);
    expect(progress.last.sentBytes, 3);
  });

  test('putStream reports a body error once', () async {
    final errors = [];
    await HttpRequestDS(_drainingClient())
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
    final ds = HttpRequestDS(
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

  test('idleTimeout does not cap an upload that keeps moving', () async {
    final progress = await HttpRequestDS(_drainingClient())
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
    final ds = HttpRequestDS(_stalledClient((_) => aborted.complete()));

    final subscription = ds
        .putStream(url: url, body: Stream.value([1]), headers: const {})
        .listen(null);
    await subscription.cancel();

    await aborted.future.timeout(const Duration(seconds: 1));
  });

  test('cancelling getStream aborts the request before the response', () async {
    final aborted = Completer<void>();
    final ds = HttpRequestDS(_stalledClient((_) => aborted.complete()));

    final subscription = ds.getStream(url: url).listen(null);
    await subscription.cancel().timeout(const Duration(seconds: 1));

    await aborted.future.timeout(const Duration(seconds: 1));
  });

  test('a timeout throws TimeoutException, not an abort', () async {
    final ds = HttpRequestDS(_stalledClient((_) {}));
    const timeout = Duration(milliseconds: 20);

    await Future.wait([
      for (final request in [
        ds.jsonRequest(url: url, timeout: timeout),
        ds.get(url: url, timeout: timeout),
        ds.post(url: url, body: 'x', timeout: timeout),
        ds.getStream(url: url, idleTimeout: timeout).toList(),
        ds
            .putStream(url: url, body: Stream.value([1]), idleTimeout: timeout)
            .toList(),
      ])
        expectLater(request, throwsA(isA<TimeoutException>())),
    ]);
  });

  test('getStream times out when the body stalls', () async {
    final ds = HttpRequestDS(
      MockClient.streaming((request, _) async {
        final body = StreamController<List<int>>()..add([1]);
        (request as http.Abortable).abortTrigger!.whenComplete(() {
          body.addError(http.RequestAbortedException(request.url));
          body.close();
        });
        return http.StreamedResponse(body.stream, 200);
      }),
    );

    final received = <List<int>>[];
    final failed = Completer<Object>();
    ds
        .getStream(url: url, idleTimeout: const Duration(milliseconds: 20))
        .listen(received.add, onError: failed.complete);

    expect(await failed.future, isA<TimeoutException>());
    expect(received, [
      [1],
    ]);
  });

  test('idleTimeout does not cap a download that keeps moving', () async {
    final ds = HttpRequestDS(
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

    final chunks = await ds
        .getStream(url: url, idleTimeout: const Duration(milliseconds: 100))
        .toList();

    expect(chunks, hasLength(15));
  });

  test(
    'a paused getStream does not time out, even before the response',
    () async {
      final respond = Completer<void>();
      final body = StreamController<List<int>>();
      final ds = HttpRequestDS(
        MockClient.streaming((request, _) async {
          await respond.future;
          (request as http.Abortable).abortTrigger!.whenComplete(() {
            if (body.isClosed) return;
            body.addError(http.RequestAbortedException(request.url));
            body.close();
          });
          return http.StreamedResponse(body.stream, 200);
        }),
      );

      final received = <List<int>>[];
      final done = Completer<void>();
      final subscription = ds
          .getStream(url: url, idleTimeout: const Duration(milliseconds: 20))
          .listen(
            received.add,
            onError: done.completeError,
            onDone: done.complete,
          );
      await Future<void>.delayed(Duration.zero);
      subscription.pause();
      respond.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      subscription.resume();
      body
        ..add([1])
        ..close();

      await done.future;
      expect(received, [
        [1],
      ]);
    },
  );

  test('a byte body is sent as given', () async {
    final client = _RecordingClient();
    final ds = HttpRequestDS(client);
    final bytes = Uint8List.fromList([1, 2, 3]);

    await ds.put(url: url, body: bytes);
    await ds.post(url: url, body: <dynamic>[4, 5]);

    expect(client.requests[0].bodyBytes, same(bytes));
    expect(client.requests[1].bodyBytes, [4, 5]);
  });

  test('a map body is sent as form fields', () async {
    late http.Request sent;
    final ds = HttpRequestDS(
      MockClient((request) async {
        sent = request;
        return http.Response('', 200);
      }),
    );

    await ds.post(url: url, body: {'name': 'bob smith'});

    expect(sent.bodyFields, {'name': 'bob smith'});
  });

  test('a body of another type throws ArgumentError', () {
    final ds = HttpRequestDS(_drainingClient());

    expect(ds.post(url: url, body: 42), throwsArgumentError);
  });

  test('head and delete send their method', () async {
    final methods = <String>[];
    final ds = HttpRequestDS(
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
    final ds = HttpRequestDS(
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
        ds.getStream(url: url, followRedirects: false).toList(),
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
    final ds = HttpRequestDS(
      _stalledClient((request) => aborted.add(request.method)),
    );

    final requests = [
      ds.jsonRequest(url: url),
      ds.get(url: url),
      ds.post(url: url, body: 'x', headers: const <String, String>{}),
      ds.getStream(url: url).toList(),
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
