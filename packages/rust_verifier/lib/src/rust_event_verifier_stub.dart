import 'package:dostr_nip01/dostr_nip01.dart';

const _unsupported =
    'RustEventVerifier needs dart:ffi, which this platform lacks: use '
    'Bip340EventVerifier, or DostrEventVerifier from dostr_flutter.';

/// [RustEventVerifier] on platforms without `dart:ffi`, such as the web.
class RustEventVerifier implements EventVerifier {
  /// Throws [UnsupportedError]: this platform cannot call native code.
  RustEventVerifier() {
    throw UnsupportedError(_unsupported);
  }

  @override
  Future<bool> verify(Nip01Event event) => throw UnsupportedError(_unsupported);
}
