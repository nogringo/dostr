import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:test/test.dart';

final String alice = 'a' * 64;
final String bob = 'b' * 64;

// A kind:1 note served by wss://relay.primal.net, its signature checked with nak.
const realNote = r'''
{
  "id": "fcecca80ea3a2759a7e771ab132a6b82a731855cf5389850d04591fe24f65103",
  "pubkey": "ac085cdadc37af0c6941cc45d4f30a1146b59e59c1796bb78d13970bfd1dc87b",
  "created_at": 1793919623,
  "kind": 1,
  "tags": [
    ["r", "https://yosuke4061.com/uranai/ema/"],
    ["client", "midori373-stream-hub"],
    ["t", "uranai"],
    ["l", "en"],
    ["t", "MidoriPhotoArt"],
    ["t", "uranai"],
    ["t", "fortune"],
    ["t", "indiedev"],
    ["t", "御神籤"],
    ["image", "https://yosuke4061.com/uranai/ema/ogp.png"],
    ["imeta", "url https://yosuke4061.com/uranai/ema/ogp.png", "m image/png"]
  ],
  "content": "🔮 Fortune\n\nHangs a virtual wooden ema on a rack and watches it sway in the wind.\nJust a quiet little shrine simulator called \"Ema Plaque Fortune Slip\".\n\n────\nhttps://yosuke4061.com/uranai/ema/\n\nhttps://yosuke4061.com/uranai/ema/ogp.png\n\n#MidoriPhotoArt #uranai #fortune #indiedev #御神籤",
  "sig": "5d9722f97ccca4dd8f0fb10fb7d34a0782f1058ef376087f35b53f50c0d6bbf1aabb6d6edd2c2d474418021d7601ffc0090feff0ef030dfec578a774736f67ed"
}
''';

Nip01Event signedEvent({String content = '', int? createdAt}) => Nip01Event(
  pubKey: alice,
  kind: 1,
  tags: const [],
  content: content,
  createdAt: createdAt,
).copyWith(sig: 'f' * 128);

void main() {
  group('Nip01Event', () {
    test('gives a real note the id its author signed', () {
      final note = jsonDecode(realNote) as Map<String, dynamic>;
      final event = Nip01Event(
        pubKey: note['pubkey'],
        createdAt: note['created_at'],
        kind: note['kind'],
        tags: [for (final tag in note['tags']) List<String>.from(tag)],
        content: note['content'],
      );

      expect(event.id, note['id']);
    });

    group('copyWith', () {
      final event = signedEvent(content: 'original', createdAt: 1);

      test('gives a changed payload its own id and drops the signature', () {
        final changes = [
          event.copyWith(pubKey: bob),
          event.copyWith(createdAt: 2),
          event.copyWith(kind: 7),
          event.copyWith(
            tags: [
              ['t', 'x'],
            ],
          ),
          event.copyWith(content: 'changed'),
        ];

        for (final changed in changes) {
          expect(changed.id, isNot(event.id));
          expect(changed.hasValidId, isTrue);
          expect(changed.sig, isNull);
        }
      });

      test('keeps the signature when the payload hashes to the same id', () {
        final same = event.copyWith(content: 'original');

        expect(same.id, event.id);
        expect(same.sig, event.sig);
      });

      test('keeps the signature of the new payload when given one', () {
        final resigned = event.copyWith(content: 'changed', sig: 'e' * 128);

        expect(resigned.hasValidId, isTrue);
        expect(resigned.sig, 'e' * 128);
      });

      test('keeps an id it is given, even one the payload does not match', () {
        final forged = event.copyWith(id: event.id, content: 'changed');

        expect(forged.id, event.id);
        expect(forged.hasValidId, isFalse);
        expect(forged.sig, event.sig);
      });

      test('keeps everything when nothing signed changes', () {
        final copy = event.copyWith();

        expect(copy.id, event.id);
        expect(copy.sig, event.sig);
      });
    });

    test('takes the current time when created_at is omitted', () {
      final before = Nip01Event.secondsSinceEpoch();

      final event = Nip01Event(pubKey: alice, kind: 1, tags: [], content: '');

      expect(event.createdAt, greaterThanOrEqualTo(before));
    });

    test('keeps a created_at of 0', () {
      final event = Nip01Event(
        pubKey: alice,
        createdAt: 0,
        kind: 1,
        tags: [],
        content: '',
      );

      expect(event.createdAt, 0);
      expect(
        event.id,
        sha256
            .convert(utf8.encode(jsonEncode([0, alice, 0, 1, [], ''])))
            .toString(),
      );
    });

    test('copies its tags and refuses changes to them', () {
      final tags = [
        ['p', bob],
      ];
      final event = Nip01Event(pubKey: alice, kind: 1, tags: tags, content: '');

      tags.add(['t', 'later']);
      tags.first.add('extra');

      expect(event.tags, [
        ['p', bob],
      ]);
      expect(event.hasValidId, isTrue);
      expect(() => event.tags.add(['t', 'x']), throwsUnsupportedError);
      expect(() => event.tags.first.add('x'), throwsUnsupportedError);
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

      expect(event.getFirstTag('e'), 'root');
      expect(event.pTags, [bob]);
      expect(event.dTag, 'slug');
      expect(event.tTags, ['Nostr']);
      expect(event.getFirstTag('x'), isNull);
    });

    test('getTags keeps values as the event holds them', () {
      final event = Nip01Event(
        pubKey: alice,
        kind: 1,
        tags: [
          ['d', 'MyList'],
          ['d', ' padded '],
        ],
        content: '',
      );

      expect(event.getTags('d'), ['MyList', ' padded ']);
    });
  });

  group('JSON', () {
    final note = jsonDecode(realNote) as Map<String, dynamic>;

    test('reads a real note', () {
      final event = Nip01Event.fromJson(note);

      expect(event.id, note['id']);
      expect(event.pubKey, note['pubkey']);
      expect(event.createdAt, note['created_at']);
      expect(event.kind, note['kind']);
      expect(event.tags, note['tags']);
      expect(event.content, note['content']);
      expect(event.sig, note['sig']);
      expect(event.hasValidId, isTrue);
    });

    test('writes back the JSON it read', () {
      final event = Nip01Event.fromJson(note);

      expect(event.toJson(), note);
      expect(jsonDecode(event.toJsonString()), note);
      expect(jsonDecode(jsonEncode(event)), note);
    });

    test('reads unsigned and loosely typed JSON', () {
      final event = Nip01Event.fromJson({
        'created_at': 1,
        'kind': 1,
        'tags': [
          ['t', 5],
          'not a tag',
          ['p', null],
        ],
      });

      expect(event.hasValidId, isTrue);
      expect(event.pubKey, '');
      expect(event.content, '');
      expect(event.sig, isNull);
      expect(event.tags, [
        ['t', '5'],
        ['p', ''],
      ]);
      expect(() => event.tags.first.add('x'), throwsUnsupportedError);
    });

    test('gives events read without an id their own ids', () {
      final first = Nip01Event.fromJson({
        'created_at': 1,
        'kind': 1,
        'content': 'a',
      });
      final second = Nip01Event.fromJson({
        'created_at': 1,
        'kind': 1,
        'content': 'b',
      });

      expect({first, second}, hasLength(2));
    });

    test('writes no sig for an unsigned event', () {
      final event = Nip01Event(pubKey: alice, kind: 1, tags: [], content: '');

      expect(event.toJson(), isNot(contains('sig')));
      expect(Nip01Event.fromJson(event.toJson()).sig, isNull);
    });

    test('throws a FormatException for a field it cannot read', () {
      for (final data in [
        {'kind': 1},
        {'created_at': 1},
        {'created_at': 1.5, 'kind': 1},
        {'created_at': 1, 'kind': '1'},
        {'created_at': 1, 'kind': 1, 'id': 5},
        {'created_at': 1, 'kind': 1, 'pubkey': 5},
        {'created_at': 1, 'kind': 1, 'sig': 5},
        {'created_at': 1, 'kind': 1, 'tags': 't'},
      ]) {
        expect(
          () => Nip01Event.fromJson(data),
          throwsFormatException,
          reason: '$data',
        );
      }
    });

    test('tryFromJson reads a real note', () {
      final event = Nip01Event.tryFromJson(note)!;

      expect(event.toJson(), note);
      expect(event.hasValidId, isTrue);
    });

    test('tryFromJson reads an event without id or sig', () {
      final payload = {
        'pubkey': alice,
        'created_at': 1,
        'kind': 1,
        'tags': [
          ['t', 'x'],
        ],
        'content': '',
      };

      for (final data in [
        payload,
        {...payload, 'sig': null},
      ]) {
        final event = Nip01Event.tryFromJson(data)!;
        expect(event.hasValidId, isTrue);
        expect(event.sig, isNull);
      }
    });

    test('tryFromJson refuses what is not a well-formed event', () {
      final payload = {
        'pubkey': alice,
        'created_at': 1,
        'kind': 1,
        'tags': <Object?>[],
        'content': '',
      };

      for (final data in <Object?>[
        null,
        'event',
        [payload],
        {...payload}..remove('pubkey'),
        {...payload}..remove('content'),
        {...payload}..remove('tags'),
        {...payload, 'created_at': 1.5},
        {...payload, 'kind': '1'},
        {
          ...payload,
          'tags': [
            ['t', 5],
          ],
        },
        {
          ...payload,
          'tags': ['t'],
        },
        {...payload, 'id': 5},
        {...payload, 'sig': 5},
      ]) {
        expect(Nip01Event.tryFromJson(data), isNull, reason: '$data');
      }
    });
  });

  test('hasValidId tells a forged id apart', () {
    final note = jsonDecode(realNote) as Map<String, dynamic>;

    expect(Nip01Event.fromJson(note).hasValidId, isTrue);
    expect(Nip01Event.fromJson({...note, 'id': 'f' * 64}).hasValidId, isFalse);
  });
}
