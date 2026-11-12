import 'package:ndk_nip01/ndk_nip01.dart';

/// Stub implementation used when neither `dart:io` nor web interop is available.
EventVerifier createNdkEventVerifier() {
  throw UnsupportedError('NdkEventVerifier is not available on this platform.');
}
