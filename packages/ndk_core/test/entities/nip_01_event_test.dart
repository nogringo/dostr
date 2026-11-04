import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  group('Nip01Event', () {
    test('its id is the sha256 of the NIP-01 serialization', () {
      final event = Nip01Event(
        pubKey: alice,
        createdAt: 1700000000,
        kind: 1,
        tags: [
          ['p', bob],
          ['t', 'nostr'],
        ],
        content: 'a "quoted"\nline',
      );
      final serialized = jsonEncode([
        0,
        alice,
        1700000000,
        1,
        [
          ['p', bob],
          ['t', 'nostr'],
        ],
        'a "quoted"\nline',
      ]);

      expect(event.id, sha256.convert(utf8.encode(serialized)).toString());
      expect(Nip01Utils.isIdValid(event), isTrue);
    });

    test('copyWith keeps the id, so a changed payload no longer matches', () {
      final event = signedEvent(content: 'original', createdAt: 1);

      final changed = event.copyWith(content: 'changed');

      expect(changed.id, event.id);
      expect(Nip01Utils.isIdValid(changed), isFalse);
    });

    test('takes the current time when created at 0', () {
      final before = Nip01Event.secondsSinceEpoch();

      final event = Nip01Event(pubKey: alice, kind: 1, tags: [], content: '');

      expect(event.createdAt, greaterThanOrEqualTo(before));
    });

    test('events with the same id are equal', () {
      final event = signedEvent(createdAt: 1);

      expect(event.copyWith(sig: 'other'), event);
      expect(event.copyWith(sig: 'other').hashCode, event.hashCode);
    });

    test('reads its tags', () {
      final event = Nip01Event(
        pubKey: alice,
        kind: 1,
        tags: [
          ['e', 'root', '', 'root'],
          ['e', 'parent', '', 'reply'],
          ['p', bob],
          ['d', 'slug'],
          ['t', 'Nostr'],
          ['x'],
        ],
        content: '',
      );

      expect(event.getEId(), 'root');
      expect(event.replyETags, ['parent']);
      expect(event.pTags, [bob]);
      expect(event.getDtag(), 'slug');
      expect(event.tTags, ['nostr']);
      expect(event.getFirstTag('x'), isNull);
    });
  });

  group('Nip01EventModel', () {
    test('round-trips through JSON', () {
      final event = signedEvent(
        content: 'hello',
        createdAt: 42,
        tags: [
          ['p', bob],
        ],
      );

      final decoded = Nip01EventModel.fromJson(
        jsonDecode(Nip01EventModel.fromEntity(event).toJsonString()),
      );

      expect(decoded.id, event.id);
      expect(decoded.sig, event.sig);
      expect(decoded.tags, event.tags);
      expect(decoded.validSig, isNull);
    });
  });
}
