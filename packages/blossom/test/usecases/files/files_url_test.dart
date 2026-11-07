import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_blossom/src/data_layer/io/file_io_platform.dart';
import 'package:ndk_blossom/src/data_layer/repositories/blossom/blossom_impl.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:test/test.dart';

final _blob = utf8.encode('a blob from a note');
final _hash = sha256.convert(_blob).toString();
final _author = Bip340.generatePrivateKey().publicKey;

/// Blossom servers on which only the hosts in [having] hold [_blob]
class _Servers {
  final Set<String> having;
  final requests = <String>[];

  _Servers(this.having);

  late final repository = BlossomRepositoryImpl(
    client: NdkHttp(
      MockClient((request) async {
        requests.add(
          '${request.method} ${request.url.host}${request.url.path}',
        );
        if (!having.contains(request.url.host) ||
            !request.url.path.endsWith('/$_hash')) {
          return http.Response('', 404);
        }
        return http.Response.bytes(request.method == 'HEAD' ? [] : _blob, 200);
      }),
    ),
    fileIO: createFileIO(),
  );
}

void main() {
  late Ndk ndk;

  setUp(() => ndk = Ndk.emptyBootstrapRelaysConfig());
  tearDown(() => ndk.destroy());

  /// Files on [servers], [lists] giving each pubkey's server list and [asked]
  /// recording whose list was read
  Files filesOn(
    _Servers servers, {
    Map<String, List<String>> lists = const {},
    List<String>? asked,
    AuthHandler? authHandler,
  }) => Files(
    Blossom(
      accounts: ndk.accounts,
      eventSignerFactory: ndk.config.eventSignerFactory,
      authHandler: authHandler,
      getUserServerList: (pubkey) async {
        asked?.add(pubkey);
        return lists[pubkey];
      },
      blossomRepository: servers.repository,
    ),
  );

  test('a blossom url alone is read from its own server', () async {
    final servers = _Servers({'cdn.example'});

    final blob = await filesOn(
      servers,
    ).download(url: 'https://cdn.example/$_hash.pdf');

    expect(blob.data, _blob);
    expect(servers.requests, ['GET cdn.example/$_hash']);
  });

  test('the path before the hash is part of the server', () async {
    final servers = _Servers({'example.com'});

    await filesOn(
      servers,
    ).download(url: 'https://example.com/blossom/$_hash.png');

    expect(servers.requests, ['GET example.com/blossom/$_hash']);
  });

  test('the url server comes before serverUrls, and only once', () async {
    final servers = _Servers({'b.example'});

    await filesOn(servers).download(
      url: 'https://a.example/$_hash',
      serverUrls: ['https://b.example', 'https://a.example/'],
    );

    expect(servers.requests, ['GET a.example/$_hash', 'GET b.example/$_hash']);
  });

  test('the author list is read once the url server failed', () async {
    final servers = _Servers({'b.example'});
    final asked = <String>[];

    final blob = await filesOn(
      servers,
      lists: {
        _author: ['https://a.example/', 'https://b.example'],
      },
      asked: asked,
    ).download(url: 'https://a.example/$_hash', pubkey: _author);

    expect(blob.data, _blob);
    expect(asked, [_author]);
    expect(servers.requests, ['GET a.example/$_hash', 'GET b.example/$_hash']);
  });

  test('a blob the url server has costs no list lookup', () async {
    final asked = <String>[];

    await filesOn(
      _Servers({'a.example'}),
      lists: {
        _author: ['https://b.example'],
      },
      asked: asked,
    ).download(url: 'https://a.example/$_hash', pubkey: _author);

    expect(asked, isEmpty);
  });

  test('a blob nobody has fails with every server, in order', () async {
    await expectLater(
      filesOn(
        _Servers({}),
        lists: {
          _author: ['https://b.example'],
        },
      ).download(url: 'https://a.example/$_hash', pubkey: _author),
      throwsA(
        isA<BlossomRequestException>()
            .having((e) => e.errors.keys, 'servers', [
              'https://a.example',
              'https://b.example',
            ])
            .having((e) => e.notFound, 'notFound', true),
      ),
    );
  });

  test('an author without a list leaves the url server failure', () async {
    await expectLater(
      filesOn(
        _Servers({}),
      ).download(url: 'https://a.example/$_hash', pubkey: _author),
      throwsA(
        isA<BlossomRequestException>().having((e) => e.errors.keys, 'servers', [
          'https://a.example',
        ]),
      ),
    );
  });

  test('require() reaches the author list when the handler keeps every '
      'first server from the identity', () async {
    final servers = _Servers({'b.example'});
    final asked = <String>[];
    final key = Bip340.generatePrivateKey();
    final account = Account(
      type: AccountType.privateKey,
      pubkey: key.publicKey,
      signer: Bip340EventSigner(
        privateKey: key.privateKey,
        publicKey: key.publicKey,
      ),
    );

    final blob =
        await filesOn(
          servers,
          lists: {
            _author: ['https://b.example'],
          },
          asked: asked,
          authHandler: (url, _) async => url != 'https://a.example',
        ).download(
          url: 'https://a.example/$_hash',
          pubkey: _author,
          auth: AuthPolicy.require(account),
        );

    expect(blob.data, _blob);
    expect(asked, [_author]);
    expect(servers.requests, ['GET b.example/$_hash']);
  });

  test('checkUrl answers the url as given when its server has it', () async {
    final url = 'https://a.example/$_hash.mp4';

    expect(await filesOn(_Servers({'a.example'})).checkUrl(url: url), url);
  });

  test('checkUrl answers where the blob is when its url is broken', () async {
    final alive = await filesOn(_Servers({'b.example'})).checkUrl(
      url: 'https://a.example/$_hash.mp4',
      serverUrls: ['https://b.example'],
    );

    expect(alive, 'https://b.example/$_hash');
  });

  test('downloadToFile reads a blossom url alone', () async {
    final dir = await Directory.systemTemp.createTemp('files_url_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/blob.pdf';

    await filesOn(
      _Servers({'a.example'}),
    ).downloadToFile(url: 'https://a.example/$_hash.pdf', outputPath: path);

    expect(File(path).readAsBytesSync(), _blob);
  });
}
