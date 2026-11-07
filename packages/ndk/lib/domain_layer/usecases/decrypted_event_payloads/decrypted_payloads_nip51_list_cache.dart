import 'package:ndk_lists/ndk_lists.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

import 'package:ndk_cache/ndk_cache.dart';
import 'decrypted_event_payloads.dart';

/// Keeps the plaintext of the private elements of [Lists] in the decrypted
/// payload sidecars.
class DecryptedPayloadsNip51ListCache implements Nip51ListPlaintextCache {
  final DecryptedEventPayloads _payloads;

  DecryptedPayloadsNip51ListCache(this._payloads);

  @override
  Future<String?> loadOrDecrypt({
    required Nip01Event event,
    required String viewerPubKey,
    required Future<String?> Function() decrypt,
  }) => _payloads.loadOrDecrypt(
    event: event,
    viewerPubKey: viewerPubKey,
    // NIP-04 ciphertext ends with ?iv=
    scheme: event.content.contains('?iv=')
        ? DecryptedPayloadScheme.nip04
        : DecryptedPayloadScheme.nip44,
    decrypt: decrypt,
  );
}
