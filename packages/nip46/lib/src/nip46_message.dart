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

final _hexPubkey = RegExp(r'^[0-9a-f]{64}$');

/// Whether [value] is a pubkey as NIP-46 writes them, in lowercase hex.
bool isHexPubkey(String value) => _hexPubkey.hasMatch(value);

/// The url of an auth challenge, or null unless it is an https one: a bunker
/// url can come from anyone, and the app may hand the challenge to a launcher.
String? httpsAuthUrl(Object? challenge) {
  if (challenge is! String) return null;
  final uri = Uri.tryParse(challenge);
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
  return challenge;
}

/// Whether every relay refused the request or never got it. A relay whose OK
/// timed out may still have passed it on.
bool noRelayTook(Map<RelayUrl, RelayPublishOutcome> outcomes) =>
    outcomes.values.every(
      (outcome) =>
          outcome.status == RelayPublishStatus.refused ||
          outcome.status == RelayPublishStatus.failed,
    );

/// Whether a relay serves [subscription], once one does or none will.
///
/// Only then does it get what is published: kind 24133 is ephemeral, so no
/// relay keeps it for a REQ that comes later.
Future<bool> isServed(RelayReq subscription) async {
  await for (final outcomes in subscription.outcomesStream) {
    if (outcomes.values.any(
      (outcome) => outcome.status == RelayRequestStatus.eose,
    )) {
      return true;
    }
  }
  return false;
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
