import 'nip_01_event.dart';

/// The interface of the signature verifiers, such as those of `dostr_bip340`
/// and `dostr_rust_verifier`.
abstract interface class EventVerifier {
  /// Whether the id of [event] matches its payload and its sig is a valid
  /// signature of that id by its pubkey.
  Future<bool> verify(Nip01Event event);
}
