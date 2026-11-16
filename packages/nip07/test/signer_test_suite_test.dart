@TestOn('browser')
library;

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';
import 'package:test/test.dart';

import 'fake_nostr_extension.dart';

void main() {
  injectSetupCode();

  setUp(setupNostrExtension);
  tearDown(() => eval('window.nostr = null;'));

  runSignerTestSuite(
    name: 'Nip07Signer',
    createSigner: () =>
        Nip07Signer(publicKey: Bip340.getPublicKey(extensionPrivateKey)),
    createPeer: const Bip340SignerFactory().createWithNewKeyPair,
    verifier: Bip340EventVerifier(),
    interactive: true,
  );
}
