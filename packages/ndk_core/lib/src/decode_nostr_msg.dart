import 'dart:convert';

import '../domain_layer/entities/nip_01_event.dart';
import 'nostr_message_raw.dart';

/// Decodes a relay message. One that misses a field, or carries one of the
/// wrong type, comes back as [NostrMessageRawType.invalid], so the handler of
/// each other type can trust its shape.
NostrMessageRaw decodeNostrMsg(String msgJsonStr) {
  try {
    final decoded = jsonDecode(msgJsonStr);
    return switch (decoded) {
      ['NOTICE', String _, ...] => NostrMessageRaw(
        type: NostrMessageRawType.notice,
        otherData: decoded,
      ),
      ['EVENT', String requestId, Map eventData, ...] => NostrMessageRaw(
        type: NostrMessageRawType.event,
        nip01Event: _decodeEvent(eventData),
        requestId: requestId,
      ),
      ['EOSE', String requestId, ...] => NostrMessageRaw(
        type: NostrMessageRawType.eose,
        requestId: requestId,
        otherData: decoded,
      ),
      ['OK', String _, bool _, ...] => NostrMessageRaw(
        type: NostrMessageRawType.ok,
        otherData: decoded,
      ),
      ['CLOSED', String _, ...] => NostrMessageRaw(
        type: NostrMessageRawType.closed,
        otherData: decoded,
      ),
      ['AUTH', String _, ...] => NostrMessageRaw(
        type: NostrMessageRawType.auth,
        otherData: decoded,
      ),
      ['NOTICE' || 'EVENT' || 'EOSE' || 'OK' || 'CLOSED' || 'AUTH', ...] =>
        NostrMessageRaw(type: NostrMessageRawType.invalid, otherData: decoded),
      [String _, ...] => NostrMessageRaw(
        type: NostrMessageRawType.unknown,
        otherData: decoded,
      ),
      _ => NostrMessageRaw(
        type: NostrMessageRawType.invalid,
        otherData: msgJsonStr,
      ),
    };
  } catch (e) {
    return NostrMessageRaw(
      type: NostrMessageRawType.invalid,
      otherData: msgJsonStr,
    );
  }
}

Nip01Event _decodeEvent(Map eventData) => Nip01Event(
  id: eventData['id'],
  pubKey: eventData['pubkey'],
  createdAt: eventData['created_at'],
  kind: eventData['kind'],
  tags: (eventData['tags'] as List)
      .map((tag) => List<String>.from(tag))
      .toList(),
  content: eventData['content'],
  sig: eventData['sig'],
  validSig: null,
);
