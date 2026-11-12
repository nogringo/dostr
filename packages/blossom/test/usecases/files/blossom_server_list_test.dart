import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_blossom/src/data_layer/io/file_io_platform.dart';
import 'package:dostr_blossom/src/data_layer/repositories/blossom/blossom_impl.dart';
import 'package:test/test.dart';

final _sha256 = 'ab' * 32;

Matcher _noServerList(String? pubkey) => throwsA(
  isA<BlossomNoServerListException>().having((e) => e.pubkey, 'pubkey', pubkey),
);

void main() {
  late Accounts accounts;
  late List<http.BaseRequest> requests;

  setUp(() {
    accounts = Accounts(const Bip340EventSignerFactory());
    requests = [];
  });
  tearDown(() {
    expect(requests, isEmpty, reason: 'nothing may be sent');
    return accounts.dispose();
  });

  Blossom blossomWith(List<String>? list) => Blossom(
    accounts: accounts,
    eventSignerFactory: const Bip340EventSignerFactory(),
    getUserServerList: (_) async => list,
    blossomRepository: BlossomRepositoryImpl(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('', 500);
      }),
      fileIO: createFileIO(),
    ),
  );

  String login() {
    final key = Bip340.generatePrivateKey();
    accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
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
}
