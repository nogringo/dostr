@TestOn('browser')
library;

import 'package:dostr_event_verifier_test_suite/dostr_event_verifier_test_suite.dart';
import 'package:dostr_noble/dostr_noble.dart';
import 'package:test/test.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'WebEventVerifier',
    createVerifier: WebEventVerifier.new,
    createSigner: const WebSignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
