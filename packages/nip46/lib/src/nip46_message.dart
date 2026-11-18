import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';

import 'bunker_request.dart';

/// [request] to [remotePubkey], NIP-44 encrypted and signed by [localSigner].
Future<Nip01Event> signedRequestEvent(
  NostrSigner localSigner,
  BunkerRequest request, {
  required String remotePubkey,
}) async {
  final content = await localSigner.encryptNip44(
    plaintext: jsonEncode(request),
    recipientPubkey: remotePubkey,
  );
  return localSigner.sign(
    Nip01Event(
      pubkey: localSigner.publicKey,
      kind: BunkerRequest.kKind,
      tags: [
        ['p', remotePubkey],
      ],
      content: content,
    ),
  );
}

/// The NIP-46 message [event] carries to [localSigner], or null when it does
/// not decrypt to a JSON object.
Future<Map<String, dynamic>?> readMessage(
  NostrSigner localSigner,
  Nip01Event event,
) async {
  try {
    final message = jsonDecode(
      await localSigner.decryptNip44(
        ciphertext: event.content,
        senderPubkey: event.pubkey,
      ),
    );
    return message is Map<String, dynamic> ? message : null;
  } catch (_) {
    return null;
  }
}
