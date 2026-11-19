@TestOn('browser')
library;

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_noble/dostr_noble.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';
import 'package:test/test.dart';

void main() {
  runLocalSignerFactoryTestSuite(
    name: 'WebSignerFactory',
    factory: const WebSignerFactory(),
    verifier: Bip340EventVerifier(),
    createPeer: const Bip340SignerFactory().createWithNewKeyPair,
  );
}
