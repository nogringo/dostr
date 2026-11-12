@TestOn('browser')
library;

import 'package:dostr_event_verifier_test_suite/dostr_event_verifier_test_suite.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';
import 'package:test/test.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'WebEventVerifier',
    createVerifier: WebEventVerifier.new,
    createSigner: const WebEventSignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
