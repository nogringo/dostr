import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nip11/ndk_nip11.dart';
import 'package:test/test.dart';

RelayInfoHttpRepoImpl _answering(http.Response response) =>
    RelayInfoHttpRepoImpl(
      httpDS: NdkHttp(MockClient((_) async => response)),
      maxBytes: 64,
    );

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
          isA<HttpRequestException>().having(
            (e) => e.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
    }
  });

  test('a relay that cannot be reached throws', () {
    final repo = RelayInfoHttpRepoImpl(
      httpDS: NdkHttp(
        MockClient(
          (request) async =>
              throw http.ClientException('connection refused', request.url),
        ),
      ),
    );

    expect(repo.getRelayInfo(url), throwsA(isA<http.ClientException>()));
  });

  test('a url that is not ws, wss, http or https throws ArgumentError', () {
    final repo = _answering(http.Response('{}', 200));

    for (final url in ['relay.example', 'ftp://relay.example', '::']) {
      expect(repo.getRelayInfo(url), throwsArgumentError, reason: url);
    }
  });
}
