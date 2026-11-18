@TestOn('vm')
library;

import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// without TestWidgetsFlutterBinding, which blocks the websocket to the relay
void main() {
  late MockRelay relay;
  late MockRemoteSigner remoteSigner;
  late TestDostrFlutter dostr;

  setUp(() async {
    relay = MockRelay();
    await relay.start();
    remoteSigner = MockRemoteSigner([relay]);
    dostr = TestDostrFlutter();
    dostr.accounts.loginPublicKey(pubkey: bobPubkey);
    dostr.accounts.loginExternalSigner(
      signer: await dostr.dostrFlutter.bunkers.createSigner(
        BunkerConnection(
          privateKey: alicePrivateKey,
          remotePubkey: MockRemoteSigner.publicKey,
          relays: [relay.url],
        ),
      ),
    );
  });

  tearDown(() async {
    await dostr.dispose();
    await relay.stop();
  });

  test('logout ends the session on the bunker', () async {
    await dostr.dostrFlutter.logout();

    expect(remoteSigner.receivedMethods.last, 'logout');
    expect(dostr.accounts.hasAccount(MockRemoteSigner.publicKey), isFalse);
    expect(dostr.accounts.isLoggedIn, isFalse);
  });

  test('removeAccount ends the session on the bunker', () async {
    dostr.accounts.switchAccount(pubkey: bobPubkey);

    await dostr.dostrFlutter.removeAccount(pubkey: MockRemoteSigner.publicKey);

    expect(remoteSigner.receivedMethods.last, 'logout');
    expect(dostr.accounts.hasAccount(MockRemoteSigner.publicKey), isFalse);
    expect(dostr.accounts.loggedPubkey, bobPubkey);
  });

  test('removeAccount sends no logout for another account', () async {
    await dostr.dostrFlutter.removeAccount(pubkey: bobPubkey);

    expect(remoteSigner.receivedMethods, isNot(contains('logout')));
    expect(dostr.accounts.hasAccount(bobPubkey), isFalse);
  });
}
