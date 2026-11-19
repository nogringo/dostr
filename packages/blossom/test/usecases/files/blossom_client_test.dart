import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_blossom/src/data_layer/io/file_io_platform.dart';
import 'package:dostr_blossom/src/data_layer/repositories/blossom/http_blossom_repository.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _blob = Uint8List.fromList([1, 2, 3]);
final _hash = sha256.convert(_blob).toString();
const _server = 'https://a.example';

/// Stores what it is sent and serves it back, and remembers being closed.
class _Client extends http.BaseClient {
  final requests = <String>[];
  var closed = false;

  late final _inner = MockClient((request) async {
    requests.add('${request.method} ${request.url.host}${request.url.path}');
    if (request.method == 'PUT') {
      return http.Response(
        jsonEncode({'url': '$_server/$_hash', 'sha256': _hash, 'size': 3}),
        200,
      );
    }
    return http.Response.bytes(_blob, 200);
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() => closed = true;
}

void main() {
  test('a read needs no accounts, signer factory or server list', () async {
    final client = _Client();

    final blob = await Blossom(
      httpClient: client,
    ).getBlob(sha256: _hash, serverUrls: [_server]);

    expect(blob.data, _blob);
    expect(client.requests, ['GET a.example/$_hash']);
  });

  test('without a server list, a pubkey has none', () async {
    await expectLater(
      Blossom(
        httpClient: _Client(),
      ).getBlob(sha256: _hash, pubkeyToFetchUserServerList: 'cd' * 32),
      throwsA(isA<BlossomNoServerListException>()),
    );
  });

  test('a throwaway key takes a signer factory', () async {
    final client = _Client();

    await expectLater(
      Blossom(
        httpClient: client,
      ).uploadBlob(data: _blob, serverUrls: [_server]),
      throwsStateError,
    );
    expect(client.requests, isEmpty);
  });

  test('an identity named with auth takes no signer factory', () async {
    final client = _Client();
    final signer = const Bip340SignerFactory().createWithNewKeyPair();

    final results = await Blossom(httpClient: client).uploadBlob(
      data: _blob,
      serverUrls: [_server],
      auth: AuthPolicy.require(signer),
    );

    expect(results.single.success, isTrue);
    expect(client.requests, ['PUT a.example/upload']);
  });

  test('close closes the client it made', () {
    final client = _Client();
    final blossom = http.runWithClient(Blossom.new, () => client);

    blossom.close();

    expect(client.closed, isTrue);
  });

  test('close leaves open the client it was given', () {
    final client = _Client();

    Blossom(httpClient: client).close();

    expect(client.closed, isFalse);
  });

  test('an httpClient and a blossomRepository cannot go together', () {
    expect(
      () => Blossom(
        httpClient: _Client(),
        blossomRepository: HttpBlossomRepository(
          client: _Client(),
          fileIO: createFileIO(),
        ),
      ),
      throwsArgumentError,
    );
  });
}
