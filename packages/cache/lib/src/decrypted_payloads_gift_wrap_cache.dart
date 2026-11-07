import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_nip59/ndk_nip59.dart';

import 'decrypted_event_payloads.dart';
import 'event_cache_records.dart';

/// Keeps [GiftWrap] plaintext in the decrypted payload sidecars.
class DecryptedPayloadsGiftWrapCache implements GiftWrapCache {
  final DecryptedEventPayloads _payloads;

  DecryptedPayloadsGiftWrapCache(this._payloads);

  @override
  Future<String?> loadCachedPlaintext({
    required String eventId,
    required String viewerPubKey,
  }) => _payloads.loadCachedPlaintext(
    eventId: eventId,
    viewerPubKey: viewerPubKey,
  );

  @override
  Future<String?> loadOrDecrypt({
    required Nip01Event event,
    required String viewerPubKey,
    required Future<String?> Function() decrypt,
  }) => _payloads.loadOrDecrypt(
    event: event,
    viewerPubKey: viewerPubKey,
    scheme: event.kind == GiftWrap.kGiftWrapEventkind
        ? DecryptedPayloadScheme.giftWrap
        : DecryptedPayloadScheme.nip44,
    decrypt: decrypt,
  );
}
