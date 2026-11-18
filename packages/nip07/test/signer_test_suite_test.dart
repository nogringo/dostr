@TestOn('browser')
library;

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';
import 'package:test/test.dart';

import 'fake_extension.dart';
import 'window_nostr.dart';

void main() {
  setUp(() => installWindowNostr(FakeExtension()));
  tearDown(removeWindowNostr);

  runSignerTestSuite(
    name: 'Nip07Signer through window.nostr',
    createSigner: () => Nip07Signer(publicKey: extensionPubkey),
    createPeer: const Bip340SignerFactory().createWithNewKeyPair,
    verifier: Bip340EventVerifier(),
    interactive: true,
  );
}
