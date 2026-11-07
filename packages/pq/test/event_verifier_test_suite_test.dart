import 'package:ndk_event_verifier_test_suite/ndk_event_verifier_test_suite.dart';
import 'package:ndk_pq/ndk_pq.dart';

void main() {
  for (final level in [44, 65, 87]) {
    runEventVerifierTestSuite(
      name: 'QsRustEventVerifier ML-DSA-$level',
      createVerifier: () => QsRustEventVerifier(level: level),
      createSigner: () => QsRustEventSigner(
        keypair: QsRustEventSigner.generateKeypair(level: level),
        level: level,
      ),
    );
  }
}
