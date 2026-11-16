@TestOn('browser')
library;

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';
import 'package:test/test.dart';

void main() {
  runLocalSignerFactoryTestSuite(
    name: 'WebSignerFactory',
    factory: const WebSignerFactory(),
    verifier: Bip340EventVerifier(),
    createPeer: const Bip340SignerFactory().createWithNewKeyPair,
  );
}
