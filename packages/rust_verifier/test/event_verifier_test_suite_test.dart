import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_event_verifier_test_suite/ndk_event_verifier_test_suite.dart';
import 'package:ndk_rust_verifier/ndk_rust_verifier.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'RustEventVerifier',
    createVerifier: RustEventVerifier.new,
    createSigner: const Bip340EventSignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
