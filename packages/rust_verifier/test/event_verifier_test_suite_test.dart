import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_event_verifier_test_suite/dostr_event_verifier_test_suite.dart';
import 'package:dostr_rust_verifier/dostr_rust_verifier.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'RustEventVerifier',
    createVerifier: RustEventVerifier.new,
    createSigner: const Bip340EventSignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
