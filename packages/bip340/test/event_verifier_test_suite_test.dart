import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_event_verifier_test_suite/ndk_event_verifier_test_suite.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'Bip340EventVerifier',
    createVerifier: Bip340EventVerifier.new,
    createSigner: const Bip340EventSignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );

  runEventVerifierTestSuite(
    name: 'Bip340EventVerifier without isolate',
    createVerifier: () => Bip340EventVerifier(useIsolate: false),
    createSigner: const Bip340EventSignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
