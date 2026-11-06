import 'package:ndk_nip01/ndk_nip01.dart';

/// Where [GiftWrap] keeps the plaintext of the gift wraps and seals it
/// decrypts, per event id and viewer pubkey.
abstract interface class GiftWrapCache {
  /// Cached plaintext of [eventId] for [viewerPubKey], or null.
  Future<String?> loadCachedPlaintext({
    required String eventId,
    required String viewerPubKey,
  });

  /// Cached plaintext of [event] for [viewerPubKey], otherwise the result of
  /// [decrypt], which is then cached.
  Future<String?> loadOrDecrypt({
    required Nip01Event event,
    required String viewerPubKey,
    required Future<String?> Function() decrypt,
  });
}
