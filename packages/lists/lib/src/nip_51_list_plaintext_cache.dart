import 'package:ndk_nip01/ndk_nip01.dart';

/// Where [Lists] keeps the plaintext of the private elements it decrypts, per
/// event id and viewer pubkey. NDK keeps it in its decrypted payload sidecars.
abstract interface class Nip51ListPlaintextCache {
  /// Cached plaintext of [event] for [viewerPubKey], otherwise the result of
  /// [decrypt], which is then cached.
  Future<String?> loadOrDecrypt({
    required Nip01Event event,
    required String viewerPubKey,
    required Future<String?> Function() decrypt,
  });
}
