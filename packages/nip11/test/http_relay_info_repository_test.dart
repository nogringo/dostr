import 'dart:async';

import 'package:dostr_nip11/dostr_nip11.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

HttpRelayInfoRepository _answering(http.Response response) =>
    HttpRelayInfoRepository(MockClient((_) async => response), maxBytes: 64);

/// a client that ignores the abort trigger, as one written before it
class _IgnoringAbort extends http.BaseClient {
  final Future<http.StreamedResponse> response;

  _IgnoringAbort(this.response);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => response;
}

void main() {
  const url = 'wss://relay.example';

  test('a relay that answers without a document gives null', () async {
    for (final response in [
      http.Response('Please use a Nostr client', 200),
      http.Response('[]', 200),
      http.Response('{"name": "${'x' * 64}"}', 200),
      http.Response('{}', 404),
      http.Response('', 426),
    ]) {
      expect(
        await _answering(response).getRelayInfo(url),
        isNull,
        reason: '${response.statusCode} ${response.body}',
      );
    }
  });

  test('a status that may pass throws', () async {
    for (final status in [408, 429, 500, 503]) {
      await expectLater(
        _answering(http.Response('', status)).getRelayInfo(url),
        throwsA(
          isA<RelayInfoStatusException>().having(
            (e) => e.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
    }
  });

  test('a relay that cannot be reached throws', () {
    final repo = HttpRelayInfoRepository(
      MockClient(
        (request) async =>
            throw http.ClientException('connection refused', request.url),
      ),
    );

    expect(repo.getRelayInfo(url), throwsA(isA<http.ClientException>()));
  });

  group('with a client that ignores the abort trigger', () {
    const timeout = Duration(milliseconds: 50);

    test('the timeout holds, and a later response is cancelled', () async {
      final response = Completer<http.StreamedResponse>();
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final repo = HttpRelayInfoRepository(
        _IgnoringAbort(response.future),
        timeout: timeout,
      );

      await expectLater(
        repo.getRelayInfo(url),
        throwsA(isA<TimeoutException>()),
      );
      response.complete(http.StreamedResponse(body.stream, 200));
      await pumpEventQueue();
      expect(cancelled, isTrue);
    });

    test('the timeout cancels a body that never ends', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final repo = HttpRelayInfoRepository(
        _IgnoringAbort(Future.value(http.StreamedResponse(body.stream, 200))),
        timeout: timeout,
      );

      await expectLater(
        repo.getRelayInfo(url),
        throwsA(isA<TimeoutException>()),
      );
      expect(cancelled, isTrue);
    });
  });

  test('a document nested more than 64 levels deep gives null', () async {
    Future<RelayInfo?> nested(int depth) {
      final lists = depth - 1;
      final body = '{"x":${'[' * lists}${']' * lists}}';
      return HttpRelayInfoRepository(
        MockClient((_) async => http.Response(body, 200)),
      ).getRelayInfo(url);
    }

    expect(await nested(64), isNotNull);
    expect(await nested(65), isNull);
    expect(await nested(100000), isNull);
  });

  test(
    'brackets in a string, after an escaped quote, are not nesting',
    () async {
      final brackets = '[' * 100;
      final info = await HttpRelayInfoRepository(
        MockClient((_) async => http.Response('{"name": "\\"$brackets"}', 200)),
      ).getRelayInfo(url);

      expect(info?.name, '"$brackets');
    },
  );

  test('a url that is not ws, wss, http or https throws ArgumentError', () {
    final repo = _answering(http.Response('{}', 200));

    for (final url in ['relay.example', 'ftp://relay.example', '::']) {
      expect(repo.getRelayInfo(url), throwsArgumentError, reason: url);
    }
  });
}
