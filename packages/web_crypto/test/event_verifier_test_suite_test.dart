@TestOn('browser')
library;

import 'package:ndk_event_verifier_test_suite/ndk_event_verifier_test_suite.dart';
import 'package:ndk_web_crypto/ndk_web_crypto.dart';
import 'package:test/test.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'WebEventVerifier',
    createVerifier: WebEventVerifier.new,
    createSigner: const WebEventSignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
