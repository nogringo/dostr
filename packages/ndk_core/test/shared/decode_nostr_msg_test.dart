import 'dart:convert';

import 'package:ndk_core/src/nostr_message_raw.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_core/src/decode_nostr_msg.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  test('decodes an EVENT, never trusting a signature it carries', () {
    final event = signedEvent(content: 'hi', createdAt: 1);
    final json = Nip01EventModel.fromEntity(event).toJson()
      ..['validSig'] = true;

    final message = decodeNostrMsg(jsonEncode(['EVENT', 'sub', json]));

    expect(message.type, NostrMessageRawType.event);
    expect(message.requestId, 'sub');
    expect(message.nip01Event!.id, event.id);
    expect(message.nip01Event!.sig, fakeSig);
    expect(message.nip01Event!.validSig, isNull);
  });

  test('decodes the other relay messages', () {
    final types = {
      '["EOSE","sub"]': NostrMessageRawType.eose,
      '["OK","id",true,""]': NostrMessageRawType.ok,
      '["CLOSED","sub","auth-required: x"]': NostrMessageRawType.closed,
      '["NOTICE","hello"]': NostrMessageRawType.notice,
      '["AUTH","challenge"]': NostrMessageRawType.auth,
    };

    for (final entry in types.entries) {
      expect(decodeNostrMsg(entry.key).type, entry.value, reason: entry.key);
    }
    expect(decodeNostrMsg('["EOSE","sub"]').requestId, 'sub');
  });

  test('keeps a message it does not know for protocol handlers', () {
    final message = decodeNostrMsg('["NEG-MSG","sub","abcd"]');

    expect(message.type, NostrMessageRawType.unknown);
    expect(message.otherData, ['NEG-MSG', 'sub', 'abcd']);
  });

  test('reads malformed input as invalid instead of throwing', () {
    for (final input in [
      'not json',
      '{}',
      '[]',
      '[1]',
      '["EVENT","sub"]',
      '["EVENT",null,{}]',
      '["EVENT","sub",{"id":"x"}]',
      '["EVENT","sub",{"created_at":1,"kind":1,"tags":[],"content":""}]',
      '["EVENT","sub",{"pubkey":"a","created_at":1,"kind":1,"content":""}]',
      '["EVENT","sub",{"pubkey":"a","created_at":1,"kind":1,"tags":[["t",5]],"content":""}]',
      '["EVENT","sub",{"pubkey":"a","created_at":1,"kind":1,"tags":["t"],"content":""}]',
      '["EVENT","sub",{"pubkey":"a","created_at":1,"kind":1,"tags":[],"content":"","sig":5}]',
      '["EOSE"]',
      '["OK","id"]',
      '["OK",1,true]',
      '["OK","id","true"]',
      '["CLOSED"]',
      '["NOTICE",5]',
      '["AUTH"]',
    ]) {
      expect(
        decodeNostrMsg(input).type,
        NostrMessageRawType.invalid,
        reason: input,
      );
    }
  });

  test('accepts the optional message of an OK or a CLOSED in any shape', () {
    expect(decodeNostrMsg('["OK","id",true]').type, NostrMessageRawType.ok);
    expect(
      decodeNostrMsg('["OK","id",false,null]').type,
      NostrMessageRawType.ok,
    );
    expect(decodeNostrMsg('["CLOSED","sub"]').type, NostrMessageRawType.closed);
  });
}
