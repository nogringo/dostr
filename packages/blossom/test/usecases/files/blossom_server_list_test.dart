import 'dart:typed_data';

import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_blossom/src/data_layer/io/file_io_platform.dart';
import 'package:dostr_blossom/src/data_layer/repositories/blossom/http_blossom_repository.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _sha256 = 'ab' * 32;

Matcher _noServerList(String? pubkey) => throwsA(
  isA<BlossomNoServerListException>().having((e) => e.pubkey, 'pubkey', pubkey),
);

void main() {
  late Accounts accounts;
  late List<http.BaseRequest> requests;

  setUp(() {
    accounts = Accounts(const Bip340SignerFactory());
    requests = [];
  });
  tearDown(() {
    expect(requests, isEmpty, reason: 'nothing may be sent');
    return accounts.dispose();
  });

  Blossom blossomWith(List<String>? list) => Blossom(
    accounts: accounts,
    signerFactory: const Bip340SignerFactory(),
    getUserServerList: (_) async => list,
    blossomRepository: HttpBlossomRepository(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('', 500);
      }),
      fileIO: createFileIO(),
    ),
  );

  String login() {
    final key = Bip340.generateKeyPair();
    accounts.loginPrivateKey(privkey: key.privateKey);
    return key.publicKey;
  }

  test('a read with no server and no pubkey', () async {
    await expectLater(
      blossomWith(null).getBlob(sha256: _sha256),
      _noServerList(null),
    );
  });

  for (final list in [null, <String>[]]) {
    final missing = list == null ? 'no list' : 'an empty list';

    test('a read for a pubkey with $missing', () async {
      final author = 'cd' * 32;
      await expectLater(
        blossomWith(
          list,
        ).getBlob(sha256: _sha256, pubkeyToFetchUserServerList: author),
        _noServerList(author),
      );
    });

    test('an upload for the logged-in account with $missing', () async {
      final pubkey = login();
      await expectLater(
        blossomWith(list).uploadBlob(data: Uint8List.fromList([1, 2, 3])),
        _noServerList(pubkey),
      );
    });
  }

  test('an upload with nobody logged in and no server', () async {
    await expectLater(
      blossomWith(null).uploadBlob(data: Uint8List.fromList([1, 2, 3])),
      _noServerList(null),
    );
  });

  test('a deletion for the logged-in account without a list', () async {
    final pubkey = login();
    await expectLater(
      blossomWith(null).deleteBlob(sha256: _sha256),
      _noServerList(pubkey),
    );
  });

  test('a listing for a pubkey without a list', () async {
    final author = 'cd' * 32;
    await expectLater(
      blossomWith(null).listBlobs(pubkey: author),
      _noServerList(author),
    );
  });

  for (final servers in [
    <String>[],
    ['not a url', 'https://user@a.example'],
  ]) {
    final named = servers.isEmpty ? 'no server' : 'only urls it refuses';
    final data = Uint8List.fromList([1, 2, 3]);

    test('an upload naming $named', () async {
      login();
      await expectLater(
        blossomWith([
          'https://a.example',
        ]).uploadBlob(data: data, serverUrls: servers),
        _noServerList(null),
      );
    });

    test('an anonymous upload naming $named', () async {
      await expectLater(
        blossomWith(null).uploadBlob(
          data: data,
          serverUrls: servers,
          auth: const AuthPolicy.never(),
        ),
        _noServerList(null),
      );
    });

    test('an upload check naming $named', () async {
      await expectLater(
        blossomWith(
          null,
        ).checkUpload(sha256: _sha256, contentLength: 3, serverUrls: servers),
        _noServerList(null),
      );
    });

    test('a deletion naming $named', () async {
      await expectLater(
        blossomWith(null).deleteBlob(sha256: _sha256, serverUrls: servers),
        _noServerList(null),
      );
    });

    test('a listing naming $named', () async {
      await expectLater(
        blossomWith(null).listBlobs(pubkey: 'cd' * 32, serverUrls: servers),
        _noServerList(null),
      );
    });

    test('a mirror to $named', () async {
      await expectLater(
        blossomWith(null).mirrorToServers(
          blossomUrl: Uri.parse('https://a.example/$_sha256'),
          targetServerUrls: servers,
        ),
        _noServerList(null),
      );
    });

    test('a read naming $named and no pubkey', () async {
      await expectLater(
        blossomWith(null).getBlob(sha256: _sha256, serverUrls: servers),
        _noServerList(null),
      );
    });

    test('a read naming $named reads the pubkey list at once', () async {
      final author = 'cd' * 32;
      await expectLater(
        blossomWith(null).getBlob(
          sha256: _sha256,
          serverUrls: servers,
          pubkeyToFetchUserServerList: author,
        ),
        _noServerList(author),
      );
    });
  }
}
