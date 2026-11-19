import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_blossom/src/data_layer/io/file_io_platform.dart';
import 'package:dostr_blossom/src/data_layer/repositories/blossom/http_blossom_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _blob = Uint8List.fromList(utf8.encode('a blob'));
final _hash = sha256.convert(_blob).toString();
final _owner = 'cd' * 32;

/// two spellings of a.example, then b.example
const _servers = [
  'https://a.example',
  'HTTPS://A.example:443/',
  'https://b.example',
];

void main() {
  late Accounts accounts;
  late List<String> requests;
  late Blossom blossom;

  setUp(() {
    accounts = Accounts(const Bip340SignerFactory());
    requests = [];
    blossom = Blossom(
      accounts: accounts,
      signerFactory: const Bip340SignerFactory(),
      getUserServerList: (_) async => _servers,
      blossomRepository: HttpBlossomRepository(
        client: MockClient((request) async {
          final url = request.url;
          requests.add('${request.method} ${url.host}${url.path}');
          if (url.path.startsWith('/list/')) {
            // a listing stops at the first server that answers
            return http.Response('[]', url.host == 'a.example' ? 500 : 200);
          }
          return http.Response(
            jsonEncode({
              'url': 'https://${url.host}/$_hash',
              'sha256': _hash,
              'size': _blob.length,
            }),
            200,
          );
        }),
        fileIO: createFileIO(),
      ),
    );
  });
  tearDown(() => accounts.dispose());

  test('an upload goes to each server once', () async {
    await blossom.uploadBlob(data: _blob, serverUrls: _servers);

    expect(requests, ['PUT a.example/upload', 'PUT b.example/mirror']);
  });

  test('an upload to a server list goes to each server once', () async {
    await blossom.uploadBlob(data: _blob, pubkeyToFetchUserServerList: _owner);

    expect(requests, ['PUT a.example/upload', 'PUT b.example/mirror']);
  });

  test('an upload check asks each server once', () async {
    await blossom.checkUpload(
      sha256: _hash,
      contentLength: _blob.length,
      serverUrls: _servers,
    );

    expect(
      requests,
      unorderedEquals(['HEAD a.example/upload', 'HEAD b.example/upload']),
    );
  });

  test('a mirror goes to each server once', () async {
    await blossom.mirrorToServers(
      blossomUrl: Uri.parse('https://c.example/$_hash'),
      targetServerUrls: _servers,
    );

    expect(
      requests,
      unorderedEquals(['PUT a.example/mirror', 'PUT b.example/mirror']),
    );
  });

  test('a deletion asks each server once', () async {
    await blossom.deleteBlob(sha256: _hash, serverUrls: _servers);

    expect(
      requests,
      unorderedEquals(['DELETE a.example/$_hash', 'DELETE b.example/$_hash']),
    );
  });

  test('the results name each server normalized', () async {
    final results = await blossom.deleteBlob(
      sha256: _hash,
      serverUrls: ['HTTPS://A.example:443/', 'https://b.example/'],
    );

    expect(results.map((result) => result.serverUrl), [
      'https://a.example',
      'https://b.example',
    ]);
  });

  test('a server url it refuses is never asked', () async {
    await blossom.deleteBlob(
      sha256: _hash,
      serverUrls: [
        'https://user:pass@a.example',
        'https://a.example@evil.example',
        'wss://b.example',
        'https://b.example?token=1',
        'https://b.example',
      ],
    );

    expect(requests, ['DELETE b.example/$_hash']);
  });

  test('a server list holding no server url it accepts is none', () async {
    final blossom = Blossom(
      accounts: accounts,
      signerFactory: const Bip340SignerFactory(),
      getUserServerList: (_) async => ['https://a.example@evil.example'],
    );

    await expectLater(
      blossom.listBlobs(pubkey: _owner),
      throwsA(isA<BlossomNoServerListException>()),
    );
  });

  test('a read naming only urls it refuses goes to the list', () async {
    final url = await blossom.checkBlob(
      sha256: _hash,
      serverUrls: ['https://user@a.example'],
      pubkeyToFetchUserServerList: _owner,
    );

    expect(url, 'https://a.example/$_hash');
    expect(requests, ['HEAD a.example/$_hash']);
  });

  test('a listing asks each server of the list once', () async {
    await blossom.listBlobs(pubkey: _owner);

    expect(requests, [
      'GET a.example/list/$_owner',
      'GET b.example/list/$_owner',
    ]);
  });
}
