import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_signer_test_suite/dostr_signer_test_suite.dart';

void main() {
  runLocalSignerFactoryTestSuite(
    name: 'Bip340SignerFactory',
    factory: const Bip340SignerFactory(),
    verifier: Bip340EventVerifier(),
  );
}
