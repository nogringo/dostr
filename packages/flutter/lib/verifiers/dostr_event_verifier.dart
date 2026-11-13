import 'package:dostr_nip01/dostr_nip01.dart';

import 'dostr_event_verifier_stub.dart'
    if (dart.library.io) 'dostr_event_verifier_native.dart'
    if (dart.library.js_interop) 'dostr_event_verifier_web.dart';

/// A platform-aware event verifier that automatically selects the best
/// implementation for the current platform.
///
/// - On **web**: uses `WebEventVerifier` from `dostr_web_crypto`, which calls
///   @noble/curves through JS interop for fast signature verification.
/// - On **native platforms** (Android, iOS, desktop): uses `RustEventVerifier` from `dostr_rust_verifier`.
///
/// This removes the need for conditional imports or platform checks in
/// application code.
///
/// ```dart
/// final reqs = RelayReqs(
///   relayManager: relayManager,
///   eventVerifier: DostrEventVerifier(),
/// );
/// ```
class DostrEventVerifier implements EventVerifier {
  final EventVerifier _delegate;

  DostrEventVerifier() : _delegate = createDostrEventVerifier();

  @override
  Future<bool> verify(Nip01Event event) => _delegate.verify(event);
}
