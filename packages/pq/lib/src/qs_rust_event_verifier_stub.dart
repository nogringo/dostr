import 'package:ndk_nip01/ndk_nip01.dart';

/// Stub implementation of [QsRustEventVerifier] for platforms that don't support FFI (e.g., web).
///
/// All operations throw [UnsupportedError] since Rust FFI is not available on web platforms.
class QsRustEventVerifier implements EventVerifier {
  final int level;

  QsRustEventVerifier({this.level = 87});

  @override
  Future<bool> verify(Nip01Event event) {
    throw UnsupportedError(
      'QsRustEventVerifier is not available on this platform. '
      'FFI is not supported on web.',
    );
  }
}
