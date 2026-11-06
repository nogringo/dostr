import 'dart:async';
import 'dart:convert';

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

    final json = await ds.jsonRequest(Uri.parse('http://localhost:7777/x'));

    expect(json, {'name': 'café'});
    expect(requested.scheme, 'http');
  });

  test('a non-2xx response throws HttpRequestException', () async {
    final ds = HttpRequestDS(
      MockClient(
        (_) async =>
            http.Response('nope', 401, headers: {'x-reason': 'auth required'}),
      ),
    );

    expect(
      ds.get(url: Uri.parse('https://example.com/blob')),
      throwsA(
        isA<HttpRequestException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.headers['x-reason'], 'x-reason', 'auth required'),
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
        ds.jsonRequest(url, timeout: timeout),
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

  test('HttpRequestException names the request and shortens the body', () {
    final error = HttpRequestException(
      method: 'GET',
      statusCode: 500,
      body: 'x' * 10000,
      url: 'https://example.com/blob',
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
      ds.jsonRequest(url),
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
