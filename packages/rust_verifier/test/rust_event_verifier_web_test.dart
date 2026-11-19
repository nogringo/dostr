@TestOn('browser')
library;

import 'package:dostr_rust_verifier/dostr_rust_verifier.dart';
import 'package:test/test.dart';

void main() {
  test('RustEventVerifier throws as soon as it is created', () {
    expect(RustEventVerifier.new, throwsUnsupportedError);
  });
}
