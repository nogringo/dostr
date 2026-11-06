import 'nip_01_event.dart';

abstract interface class EventVerifier {
  /// Whether the id of [event] matches its payload and its sig is a valid
  /// signature of that id by its pubkey.
  Future<bool> verify(Nip01Event event);
}
