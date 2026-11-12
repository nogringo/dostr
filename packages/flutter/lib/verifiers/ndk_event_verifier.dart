import 'package:ndk_nip01/ndk_nip01.dart';

import 'ndk_event_verifier_stub.dart'
    if (dart.library.io) 'ndk_event_verifier_native.dart'
    if (dart.library.js_interop) 'ndk_event_verifier_web.dart';

/// A platform-aware event verifier that automatically selects the best
/// implementation for the current platform.
///
/// - On **web**: uses `WebEventVerifier` from `ndk_web_crypto`, which calls
///   @noble/curves through JS interop for fast signature verification.
/// - On **native platforms** (Android, iOS, desktop): uses `RustEventVerifier` from `ndk_rust_verifier`.
///
/// This removes the need for conditional imports or platform checks in
/// application code.
///
/// ```dart
/// final reqs = RelayReqs(
///   relayManager: relayManager,
///   eventVerifier: NdkEventVerifier(),
/// );
/// ```
class NdkEventVerifier implements EventVerifier {
  final EventVerifier _delegate;

  NdkEventVerifier() : _delegate = createNdkEventVerifier();

  @override
  Future<bool> verify(Nip01Event event) => _delegate.verify(event);
}
