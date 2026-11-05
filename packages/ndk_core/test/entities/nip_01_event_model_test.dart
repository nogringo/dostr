import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
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

    test('copyWith gives a changed payload its own id', () {
      final model = Nip01EventModel.fromEntity(
        signedEvent(content: 'original', createdAt: 1),
      );

      final changed = model.copyWith(content: 'changed');

      expect(changed, isA<Nip01EventModel>());
      expect(Nip01Utils.isIdValid(changed), isTrue);
      expect(changed.sig, isNull);
    });

    test('an event created at 0 keeps its created_at and a valid id', () {
      final id = sha256
          .convert(utf8.encode(jsonEncode([0, alice, 0, 1, [], ''])))
          .toString();

      final decoded = Nip01EventModel.fromJson({
        'id': id,
        'pubkey': alice,
        'created_at': 0,
        'kind': 1,
        'tags': [],
        'content': '',
        'sig': fakeSig,
      });

      expect(decoded.createdAt, 0);
      expect(Nip01Utils.isIdValid(decoded), isTrue);
    });
  });
}
