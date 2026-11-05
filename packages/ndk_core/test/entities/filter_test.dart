import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

void main() {
  group('an empty list', () {
    test('is kept by toMap, fromMap and clone', () {
      final filter = Filter(authors: [], kinds: [1]);

      expect(filter.toMap(), {
        'authors': <String>[],
        'kinds': [1],
      });
      expect(filter.clone().authors, isEmpty);
      expect(Filter.fromMap(filter.toMap()).authors, isEmpty);
    });

    test('matches nothing (NIP-01)', () {
      expect(Filter(ids: []).matchesNothing, isTrue);
      expect(Filter(authors: []).matchesNothing, isTrue);
      expect(Filter(kinds: []).matchesNothing, isTrue);
      expect(Filter(pTags: []).matchesNothing, isTrue);
      expect(
        Filter(
          kinds: [1],
          tags: {
            'e': ['x'],
            't': [],
          },
        ).matchesNothing,
        isTrue,
      );
    });
  });

  test('absent or filled lists can match', () {
    expect(Filter().matchesNothing, isFalse);
    expect(Filter(tags: {}).matchesNothing, isFalse);
    expect(
      Filter(
        ids: ['a'],
        authors: ['b'],
        kinds: [1],
        pTags: ['c'],
      ).matchesNothing,
      isFalse,
    );
  });
}
