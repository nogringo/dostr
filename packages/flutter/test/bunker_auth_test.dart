@TestOn('vm')
library;

import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const loginAuthUrl = 'https://bunker.example/login';
const signAuthUrl = 'https://bunker.example/sign';

// without TestWidgetsFlutterBinding, which blocks the websocket to the relay
void main() {
  late MockRelay relay;
  late MockRemoteSigner remoteSigner;
  late TestDostrFlutter dostr;
  late List<String> bunkerAuthUrls;

  setUp(() async {
    relay = MockRelay();
    await relay.start();
    remoteSigner = MockRemoteSigner([relay]);
  });

  tearDown(() async {
    await dostr.dispose();
    await relay.stop();
  });

  void listen() {
    bunkerAuthUrls = [];
    dostr.dostrFlutter.bunkerAuthUrls.listen(bunkerAuthUrls.add);
  }

  Future<void> signNote() async {
    remoteSigner.authUrl = signAuthUrl;
    await dostr.accounts.getLoggedAccount()!.sign(
      Nip01Event(
        pubkey: MockRemoteSigner.publicKey,
        kind: 1,
        tags: [],
        content: 'hi',
      ),
    );
    await pumpEventQueue();
  }

  test('a restored bunker account passes its auth challenges on', () async {
    final connection = BunkerConnection(
      privateKey: alicePrivateKey,
      remotePubkey: MockRemoteSigner.publicKey,
      relays: [relay.url],
    );
    dostr = TestDostrFlutter(
      storage: {
        accountsKey: jsonEncode({
          'loggedAccount': MockRemoteSigner.publicKey,
          'accounts': [
            {
              'kind': 'bunker',
              'pubkey': MockRemoteSigner.publicKey,
              'signerSeed': jsonEncode(connection),
            },
          ],
        }),
      },
    );
    listen();
    await dostr.dostrFlutter.restoreAccountsState();

    await signNote();

    expect(bunkerAuthUrls, [signAuthUrl]);
  });

  test('a bunker login passes on the auth challenges after the login, '
      'not to its authCallback', () async {
    dostr = TestDostrFlutter();
    listen();
    remoteSigner.authUrl = loginAuthUrl;
    final loginUrls = <String>[];

    await dostr.dostrFlutter.loginWithBunkerUrl(
      'bunker://${MockRemoteSigner.publicKey}?relay=${relay.url}',
      authCallback: loginUrls.add,
    );
    await signNote();

    expect(loginUrls, contains(loginAuthUrl));
    expect(loginUrls, isNot(contains(signAuthUrl)));
    expect(bunkerAuthUrls, contains(signAuthUrl));
  });
}
