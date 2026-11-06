import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:test/test.dart';

void main() {
  test('jsonRequest decodes the body as UTF-8 over https', () async {
    late Uri requested;
    final ds = HttpRequestDS(
      MockClient((request) async {
        requested = request.url;
        return http.Response.bytes(utf8.encode('{"name":"café"}'), 200);
      }),
    );

    final json = await ds.jsonRequest('http://example.com/.well-known/x');

    expect(json, {'name': 'café'});
    expect(requested.scheme, 'https');
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
          url: Uri.parse('https://example.com/upload'),
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
}
