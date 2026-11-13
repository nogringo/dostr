import 'package:dostr_nip01/dostr_nip01.dart';

/// Stub implementation used when neither `dart:io` nor web interop is available.
EventVerifier createDostrEventVerifier() {
  throw UnsupportedError(
    'DostrEventVerifier is not available on this platform.',
  );
}
