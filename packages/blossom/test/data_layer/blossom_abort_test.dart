import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_blossom/ndk_blossom.dart';
import 'package:ndk_blossom/src/data_layer/io/file_io_platform.dart';
import 'package:ndk_blossom/src/data_layer/repositories/blossom/blossom_impl.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:test/test.dart';

const _servers = ['https://a.example', 'https://b.example'];
final _sha256 = 'ab' * 32;

/// Records each request, and answers none until it is aborted.
class _StalledServers {
  final requests = <String>[];
  final aborted = <String>[];

  late final client = MockClient.streaming((request, _) async {
    final name = '${request.method} ${request.url.host}';
    requests.add(name);
    await (request as http.Abortable).abortTrigger!;
    aborted.add(name);
    throw http.RequestAbortedException(request.url);
  });
}

BlossomRepositoryImpl _repo(http.Client client) =>
    BlossomRepositoryImpl(client: NdkHttp(client), fileIO: createFileIO());

/// lets the operation reach its first request, or whatever it waits on
Future<void> _settle() => Future<void>.delayed(Duration.zero);

final _aborted = throwsA(isA<http.RequestAbortedException>());

void main() {
  late Ndk ndk;

  setUp(() => ndk = Ndk.emptyBootstrapRelaysConfig());
  tearDown(() => ndk.destroy());

  Blossom blossomFor(
    BlossomServerListResolver getUserServerList, {
    BlossomRepository? repository,
  }) => Blossom(
    accounts: ndk.accounts,
    eventSignerFactory: ndk.config.eventSignerFactory,
    getUserServerList: getUserServerList,
    blossomRepository: repository,
  );

  for (final strategy in UploadStrategy.values) {
    test('cancelling a ${strategy.name} upload aborts its requests', () async {
      final servers = _StalledServers();

      final subscription = _repo(servers.client)
          .uploadBlob(
            dataStreamFactory: () => Stream.value([1, 2, 3]),
            contentLength: 3,
            authorization: const BlossomAuthorization.none(),
            serverUrls: _servers,
            strategy: strategy,
          )
          .listen(null);
      await _settle();
      await subscription.cancel().timeout(const Duration(seconds: 1));
      await _settle();

      expect(servers.requests, isNotEmpty);
      expect(servers.aborted, unorderedEquals(servers.requests));
    });
  }

  test('an aborted upload tries no other server', () async {
    final servers = _StalledServers();
    final repo = _repo(servers.client);

    final upload = repo
        .uploadBlob(
          dataStreamFactory: () => Stream.value([1, 2, 3]),
          contentLength: 3,
          authorization: const BlossomAuthorization.none(),
          serverUrls: _servers,
        )
        .toList();
    await _settle();
    repo.abortPending();

    await expectLater(upload, _aborted);
    expect(servers.requests, ['PUT a.example']);
  });

  test('an aborted upload to all servers ends instead of hanging', () async {
    final servers = _StalledServers();
    final repo = _repo(servers.client);

    final upload = repo
        .uploadBlob(
          dataStreamFactory: () => Stream.value([1, 2, 3]),
          contentLength: 3,
          authorization: const BlossomAuthorization.none(),
          serverUrls: _servers,
          strategy: UploadStrategy.allSimultaneous,
        )
        .toList();
    await _settle();
    repo.abortPending();

    await expectLater(upload.timeout(const Duration(seconds: 1)), _aborted);
    expect(
      servers.requests,
      unorderedEquals(['PUT a.example', 'PUT b.example']),
    );
  });

  test('an aborted read tries no other server', () async {
    final servers = _StalledServers();
    final repo = _repo(servers.client);

    final read = repo.getBlob(sha256: _sha256, serverUrls: _servers);
    await _settle();
    repo.abortPending();

    await expectLater(read, _aborted);
    expect(servers.requests, ['GET a.example']);
  });

  test(
    'a read aborted while it signs after a refusal sends nothing more',
    () async {
      final requests = <String>[];
      final repo = _repo(
        MockClient((request) async {
          requests.add('${request.method} ${request.url.host}');
          return http.Response('', 401);
        }),
      );
      final signing = Completer<Nip01Event>();

      final read = repo.getBlob(
        sha256: _sha256,
        serverUrls: _servers,
        authorization: BlossomAuthorization.onRefusal(() => signing.future),
      );
      await _settle();
      repo.abortPending();
      signing.complete(
        Nip01Event(pubKey: 'a' * 64, kind: 24242, tags: [], content: 'get'),
      );

      await expectLater(read, _aborted);
      expect(requests, ['GET a.example']);
    },
  );

  test('Blossom aborts an operation still resolving its servers', () async {
    final servers = _StalledServers();
    final serverList = Completer<List<String>?>();
    final blossom = blossomFor(
      (_) => serverList.future,
      repository: _repo(servers.client),
    );

    final read = blossom.getBlob(
      sha256: _sha256,
      pubkeyToFetchUserServerList: 'a' * 64,
    );
    await _settle();
    blossom.abortPending();
    serverList.complete(_servers);

    await expectLater(read, _aborted);
    expect(servers.requests, isEmpty);
  });

  test('Blossom aborts the requests of the client it made itself', () async {
    final servers = _StalledServers();
    final blossom = http.runWithClient(
      () => blossomFor((_) async => null),
      () => servers.client,
    );

    final read = blossom.getBlob(sha256: _sha256, serverUrls: _servers);
    await _settle();
    blossom.abortPending();

    await expectLater(read, _aborted);
    expect(servers.requests, ['GET a.example']);
  });

  test('Blossom stays usable after abortPending', () async {
    final blossom = blossomFor(
      (_) async => null,
      repository: _repo(
        MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
      ),
    );

    blossom.abortPending();
    final blob = await blossom.getBlob(
      sha256: sha256.convert([1, 2, 3]).toString(),
      serverUrls: _servers,
    );

    expect(blob.data, [1, 2, 3]);
  });
}
