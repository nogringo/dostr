import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_event_verifier_test_suite/dostr_event_verifier_test_suite.dart';

void main() {
  runEventVerifierTestSuite(
    name: 'Bip340EventVerifier',
    createVerifier: Bip340EventVerifier.new,
    createSigner: const Bip340SignerFactory().createWithNewKeyPair,
    externalEvents: bip340ExternalEvents,
  );
}
