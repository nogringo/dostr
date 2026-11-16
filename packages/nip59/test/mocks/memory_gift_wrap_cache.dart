import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip59/dostr_nip59.dart';

class MemoryGiftWrapCache implements GiftWrapCache {
  final Map<String, String> plaintexts = {};
  int decryptions = 0;

  @override
  Future<String?> loadCachedPlaintext({
    required String eventId,
    required String viewerPubkey,
  }) async => plaintexts['$eventId|$viewerPubkey'];

  @override
  Future<String> loadOrDecrypt({
    required Nip01Event event,
    required String viewerPubkey,
    required Future<String> Function() decrypt,
  }) async {
    final key = '${event.id}|$viewerPubkey';
    final cached = plaintexts[key];
    if (cached != null) return cached;
    decryptions++;
    return plaintexts[key] = await decrypt();
  }
}
