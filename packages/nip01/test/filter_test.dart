import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:test/test.dart';

void main() {
  Filter everyField() => Filter(
    ids: ['id1', 'id2'],
    authors: ['author1', 'author2'],
    kinds: [1, 2],
    search: 'search text',
    since: 1620000000,
    until: 1630000000,
    limit: 10,
    eTags: ['etag1'],
    pTags: ['ptag1'],
    tTags: ['ttag1'],
    aTags: ['atag1'],
    dTags: ['dtag1'],
    mTags: ['mtag1'],
  );

  final everyFieldOnTheWire = {
    'ids': ['id1', 'id2'],
    'authors': ['author1', 'author2'],
    'kinds': [1, 2],
    'search': 'search text',
    'since': 1620000000,
    'until': 1630000000,
    'limit': 10,
    '#e': ['etag1'],
    '#p': ['ptag1'],
    '#t': ['ttag1'],
    '#a': ['atag1'],
    '#d': ['dtag1'],
    '#m': ['mtag1'],
  };

  void expectEveryField(Filter filter) {
    expect(filter.ids, ['id1', 'id2']);
    expect(filter.authors, ['author1', 'author2']);
    expect(filter.kinds, [1, 2]);
    expect(filter.search, 'search text');
    expect(filter.since, 1620000000);
    expect(filter.until, 1630000000);
    expect(filter.limit, 10);
    expect(filter.eTags, ['etag1']);
    expect(filter.pTags, ['ptag1']);
    expect(filter.tTags, ['ttag1']);
    expect(filter.aTags, ['atag1']);
    expect(filter.dTags, ['dtag1']);
    expect(filter.mTags, ['mtag1']);
  }

  group('every field', () {
    test('is set by the constructor', () => expectEveryField(everyField()));

    test('is read by fromMap, tag keys without their #', () {
      final filter = Filter.fromMap(everyFieldOnTheWire);

      expectEveryField(filter);
      expect(
        filter.tags!.keys,
        unorderedEquals(['e', 'p', 't', 'a', 'd', 'm']),
      );
    });

    test('is written by toMap, tag keys with their #', () {
      expect(everyField().toMap(), everyFieldOnTheWire);
    });

    test('is kept by clone', () => expectEveryField(everyField().clone()));
  });

  group('tags', () {
    test('are stored without the NIP-01 #, by the constructor', () {
      final filter = Filter(
        tags: {
          '#e': ['etag1', 'etag2'],
          '#p': ['ptag1'],
        },
      );

      expect(filter.tags, {
        'e': ['etag1', 'etag2'],
        'p': ['ptag1'],
      });
    });

    test('are stored without the NIP-01 #, by the setter', () {
      final filter = Filter()
        ..tags = {
          '#p': ['ptag1'],
        };

      expect(filter.tags, {
        'p': ['ptag1'],
      });
    });

    test('cannot be written through the getter', () {
      final filter = Filter(pTags: ['ptag1']);

      expect(() => filter.tags!['#e'] = ['etag1'], throwsUnsupportedError);
      expect(() => filter.tags!['e'] = ['etag1'], throwsUnsupportedError);
      expect(filter.getTag('e'), isNull);
    });

    test('setTag and getTag take a key with or without its #', () {
      final filter = Filter()
        ..setTag('x', ['xtag1', 'xtag2'])
        ..setTag('#p', ['ptag1']);

      expect(filter.getTag('x'), ['xtag1', 'xtag2']);
      expect(filter.getTag('p'), ['ptag1']);
      expect(filter.getTag('#p'), ['ptag1']);
      expect(filter.toMap()['#p'], ['ptag1']);
    });

    test('keep a name of any length, through toMap and fromMap', () {
      final filter = Filter(
        tags: {
          'expiration': ['1'],
        },
      )..setTag('#ab', ['2']);

      expect(filter.getTag('expiration'), ['1']);
      expect(filter.getTag('ab'), ['2']);
      expect(Filter.fromMap(filter.toMap()).tags, {
        'expiration': ['1'],
        'ab': ['2'],
      });
    });
  });

  group('JSON', () {
    final malformed = <Map<String, Object?>>[
      {'ids': 'id1'},
      {
        'ids': [1],
      },
      {
        'authors': ['author1', null],
      },
      {
        'kinds': ['1'],
      },
      {'search': 5},
      {'since': '1620000000'},
      {'until': 1.5},
      {'limit': '10'},
      {'#p': 'ptag1'},
      {
        '#p': [1],
      },
    ];

    test('throws a FormatException for a malformed filter', () {
      for (final data in malformed) {
        expect(
          () => Filter.fromJson(data),
          throwsFormatException,
          reason: '$data',
        );
      }
    });

    test('ignores null fields and keys it does not know', () {
      expect(
        Filter.fromJson({'ids': null, '#p': null, 'other': 1}).toMap(),
        isEmpty,
      );
    });

    test('tryFromJson reads what fromJson reads', () {
      expect(
        Filter.tryFromJson(everyFieldOnTheWire)!.toMap(),
        everyFieldOnTheWire,
      );
    });

    test('tryFromJson returns null where fromJson throws', () {
      for (final data in <Object?>[null, 'filter', [], ...malformed]) {
        expect(Filter.tryFromJson(data), isNull, reason: '$data');
      }
    });
  });

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
