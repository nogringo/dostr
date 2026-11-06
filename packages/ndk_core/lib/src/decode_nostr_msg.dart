import 'dart:convert';

import 'package:ndk_nip01/ndk_nip01.dart';
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
      [
        'EVENT',
        String requestId,
        {
              'pubkey': String _,
              'created_at': int _,
              'kind': int _,
              'tags': List tags,
              'content': String _,
            } &&
            Map eventData,
        ...,
      ]
          when _areTags(tags) =>
        NostrMessageRaw(
          type: NostrMessageRawType.event,
          nip01Event: Nip01Event.fromJson(eventData),
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

bool _areTags(List tags) =>
    tags.every((tag) => tag is List && tag.every((value) => value is String));
