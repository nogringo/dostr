import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip13/dostr_nip13.dart';
import 'package:test/test.dart';

const _pubKey =
    '6d46059232af4d121456d1fff7fa8dadc32b02510e46e85b912b0585cf038574';

Nip01Event _event({List<List<String>> tags = const []}) => Nip01Event(
  pubKey: _pubKey,
  kind: 1,
  tags: tags,
  content: 'Hello, Nostr!',
  createdAt: 1234567890,
);

void main() {
  group('countLeadingZeroBits', () {
    test('counts single hex digits', () {
      const expected = {
        '0': 4,
        '1': 3,
        '2': 2,
        '3': 2,
        '4': 1,
        '5': 1,
        '6': 1,
        '7': 1,
        '8': 0,
        '9': 0,
        'a': 0,
        'b': 0,
        'c': 0,
        'd': 0,
        'e': 0,
        'f': 0,
      };
      for (final MapEntry(key: hex, value: zeros) in expected.entries) {
        expect(Nip13.countLeadingZeroBits(hex), zeros, reason: hex);
      }
    });

    test('counts multi-digit hex strings', () {
      expect(Nip13.countLeadingZeroBits('00f'), 8);
      expect(Nip13.countLeadingZeroBits('001'), 11);
      expect(Nip13.countLeadingZeroBits('007'), 9);
      expect(Nip13.countLeadingZeroBits('010'), 7);
      expect(Nip13.countLeadingZeroBits('100'), 3);
    });

    test('matches the NIP-13 examples', () {
      expect(Nip13.countLeadingZeroBits('002f'), 10);
      expect(
        Nip13.countLeadingZeroBits(
          '000006d8c378af1779d2feebc7603a125d99eca0ccf1085959b307f64e5dd358',
        ),
        21,
      );
    });

    test('handles edge cases', () {
      expect(Nip13.countLeadingZeroBits(''), 0);
      expect(Nip13.countLeadingZeroBits('0000'), 16);
      expect(Nip13.countLeadingZeroBits('00000'), 20);
    });
  });

  test('mineEvent meets the target difficulty', () async {
    final mined = await Nip13.mineEvent(_event(), 4, maxIterations: 100000);

    expect(Nip13.checkDifficulty(mined.id, 4), isTrue);
    expect(mined.sig, isNull);
  });

  test('mineEvent replaces an existing nonce tag', () async {
    final mined = await Nip13.mineEvent(
      _event(
        tags: [
          ['nonce', '1', '2'],
          ['t', 'pow'],
        ],
      ),
      4,
    );

    expect(mined.tags.where((tag) => tag[0] == 'nonce'), hasLength(1));
    expect(mined.tags, contains(equals(['t', 'pow'])));
    expect(Nip13.getTargetDifficultyFromEvent(mined), 4);
  });

  test('mineEvent throws when maxIterations runs out', () {
    expect(
      Nip13.mineEvent(_event(), 200, maxIterations: 10),
      throwsA(anything),
    );
  });

  test('getTargetDifficultyFromEvent is null without a nonce tag', () {
    expect(Nip13.getTargetDifficultyFromEvent(_event()), isNull);
  });

  test(
    'getTargetDifficultyFromEvent is null for a nonce tag without target',
    () {
      expect(
        Nip13.getTargetDifficultyFromEvent(
          _event(
            tags: [
              ['nonce', '12345'],
            ],
          ),
        ),
        isNull,
      );
    },
  );

  test('validateEvent checks the id against the nonce target', () {
    final minedEvent = Nip01Event.fromJson({
      "id": "00302f635d4e2059c5cdddca2c00b5f455ec6706cfd960a410acc3e9abe36100",
      "pubkey": _pubKey,
      "created_at": 1234567890,
      "kind": 1,
      "tags": [
        ["nonce", "3613431634", "10"],
      ],
      "content": "Hello, Nostr!",
      "sig": "",
    });

    expect(Nip13.validateEvent(minedEvent), isTrue);

    final invalidEvent = minedEvent.copyWith(
      id: minedEvent.id,
      tags: [
        ['nonce', '123', '14'],
      ],
    );
    expect(Nip13.validateEvent(invalidEvent), isFalse);
  });

  test('validateEvent accepts an event without a nonce tag', () {
    expect(Nip13.validateEvent(_event()), isTrue);
  });

  test('a mined event has a valid id', () async {
    final mined = await Nip13.mineEvent(_event(), 10);

    expect(Nip13.validateEvent(mined), isTrue);
    expect(mined.hasValidId, isTrue);
  });

  group('calculateCommitment', () {
    test('is 2^difficulty', () {
      expect(Nip13.calculateCommitment('0f'), BigInt.from(16));
    });

    test('is 0 without leading zero bits', () {
      expect(Nip13.calculateCommitment('ff'), BigInt.zero);
    });

    test('stays exact past 64 bits', () {
      expect(Nip13.calculateCommitment('${'0' * 18}ff'), BigInt.one << 72);
    });
  });
}
