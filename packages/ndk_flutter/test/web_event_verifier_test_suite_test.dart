@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ndk_event_verifier_test_suite/ndk_event_verifier_test_suite.dart';
import 'package:ndk_flutter/signers/src/event_signer_web.dart'
    show NdkEventSignerFactory;
import 'package:ndk_flutter/verifiers/web_event_verifier.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'WebEventVerifier',
    createVerifier: WebEventVerifier.new,
    createSigner: const NdkEventSignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
