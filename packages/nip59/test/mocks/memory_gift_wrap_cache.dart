import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip59/dostr_nip59.dart';

class MemoryGiftWrapCache implements GiftWrapCache {
  final Map<String, String> plaintexts = {};
  int decryptions = 0;

  @override
  Future<String?> loadCachedPlaintext({
    required String eventId,
    required String viewerPubKey,
  }) async => plaintexts['$eventId|$viewerPubKey'];

  @override
  Future<String?> loadOrDecrypt({
    required Nip01Event event,
    required String viewerPubKey,
    required Future<String?> Function() decrypt,
  }) async {
    final key = '${event.id}|$viewerPubKey';
    final cached = plaintexts[key];
    if (cached != null) return cached;
    decryptions++;
    final plaintext = await decrypt();
    if (plaintext != null) plaintexts[key] = plaintext;
    return plaintext;
  }
}
