import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

class FakeUrlLists {
  final Map<String, UrlListLookup> answers = {};
  final List<String> calls = [];

  void set(String pubkey, UrlListKind kind, UrlListLookup answer) =>
      answers['${kind.name}|$pubkey'] = answer;

  UrlListFn get fn => (pubkey, kind) async {
    final id = '${kind.name}|$pubkey';
    calls.add(id);
    return answers[id] ?? const UrlListLookup.unavailable('offline');
  };
}

List<String>? resolvedUrls(UrlResolution r) =>
    r is UrlsResolved ? r.urls : null;

void main() {
  group('UrlSet serialization', () {
    test('round-trips a nested set', () {
      const set = UrlSet.fallback([
        UrlSet.union([
          UrlSet.outbox('p1'),
          UrlSet.nip65('p5'),
          UrlSet.inbox('p2'),
          UrlSet.inbox('p3'),
          UrlSet.explicit(['wss://a']),
        ]),
        UrlSet.dm('p4'),
        UrlSet.private('p6'),
        UrlSet.blossom('p7'),
        UrlSet.first(2, UrlSet.inbox('p8')),
      ]);
      expect(UrlSet.fromMap(set.toMap()).toMap(), set.toMap());
    });

    test('reads maps stored by RelaySet', () {
      final set = UrlSet.fromMap({
        'type': 'union',
        'sets': [
          {
            'type': 'explicit',
            'relays': ['wss://a'],
          },
          {'type': 'outbox', 'pubkey': 'p1'},
          {
            'type': 'inbox',
            'pubkeys': ['p2', 'p3'],
          },
          {'type': 'dm', 'pubkeys': <String>[]},
        ],
      });
      final sets = (set as UnionUrls).sets;
      expect((sets[0] as ExplicitUrls).urls, ['wss://a']);
      expect((sets[1] as OutboxUrls).pubkey, 'p1');
      expect((sets[2] as UnionUrls).sets.map((s) => (s as InboxUrls).pubkey), [
        'p2',
        'p3',
      ]);
      expect((sets[3] as UnionUrls).sets, isEmpty);
      expect(set.needsLookup, isTrue);
      expect(sets[3].needsLookup, isFalse);
    });

    test('rejects an unknown type', () {
      expect(() => UrlSet.fromMap({'type': 'nope'}), throwsFormatException);
    });

    test('rejects a negative first count', () {
      expect(
        () => UrlSet.fromMap({
          'type': 'first',
          'count': -1,
          'set': const UrlSet.explicit(['wss://a']).toMap(),
        }),
        throwsFormatException,
      );
    });

    test('rejects a missing or mistyped field', () {
      for (final map in [
        {'type': 'dm'},
        {'type': 'outbox', 'pubkey': 1},
        {'type': 'explicit', 'relays': 'wss://a'},
        {
          'type': 'explicit',
          'relays': ['wss://a', 2],
        },
        {
          'type': 'inbox',
          'pubkeys': [null],
        },
        {
          'type': 'union',
          'sets': ['outbox'],
        },
        {'type': 'first', 'count': 1},
        {
          'type': 'first',
          'count': '1',
          'set': const UrlSet.explicit([]).toMap(),
        },
      ]) {
        expect(
          () => UrlSet.fromMap(map),
          throwsFormatException,
          reason: '$map',
        );
      }
    });

    test('sets describing the same tree are equal', () {
      UrlSet build(String pubkey) => UrlSet.fallback([
        UrlSet.union([
          UrlSet.explicit(['wss://a']),
          UrlSet.dm(pubkey),
        ]),
        UrlSet.first(2, UrlSet.inbox(pubkey)),
      ]);

      expect(build('p'), build('p'));
      expect(build('p').hashCode, build('p').hashCode);
      expect(UrlSet.fromMap(build('p').toMap()), build('p'));
      expect(build('p'), isNot(build('q')));
      expect(
        build('p').toString(),
        'UrlSet.fallback([UrlSet.union([UrlSet.explicit([wss://a]), '
        'UrlSet.dm(p)]), UrlSet.first(2, UrlSet.inbox(p))])',
      );
      expect(const UrlSet.dm('p'), isNot(const UrlSet.inbox('p')));
      expect(
        const UrlSet.union([UrlSet.outbox('p')]),
        isNot(const UrlSet.fallback([UrlSet.outbox('p')])),
      );
      expect(
        const UrlSet.first(1, UrlSet.outbox('p')),
        isNot(const UrlSet.first(2, UrlSet.outbox('p'))),
      );
    });

    test('only lookups need a list function', () {
      expect(const UrlSet.explicit(['wss://a']).needsLookup, isFalse);
      expect(
        const UrlSet.union([
          UrlSet.explicit(['wss://a']),
          UrlSet.union([]),
        ]).needsLookup,
        isFalse,
      );
      expect(
        const UrlSet.fallback([
          UrlSet.explicit([]),
          UrlSet.outbox('p'),
        ]).needsLookup,
        isTrue,
      );
    });

    test('kinds lists every leaf kind', () {
      expect(const UrlSet.explicit(['wss://a']).kinds, isEmpty);
      expect(
        const UrlSet.fallback([
          UrlSet.blossom('p'),
          UrlSet.union([
            UrlSet.dm('p'),
            UrlSet.explicit(['wss://a']),
          ]),
        ]).kinds,
        {UrlListKind.blossom, UrlListKind.dm},
      );
    });
  });

  group('resolveUrlSet', () {
    test('union merges every list and treats notFound as empty', () async {
      final lists = FakeUrlLists()
        ..set('p1', UrlListKind.outbox, const UrlListLookup.found(['wss://w']))
        ..set('p2', UrlListKind.inbox, const UrlListLookup.found(['wss://r']))
        ..set('p3', UrlListKind.inbox, const UrlListLookup.notFound());
      final r = await resolveUrlSet(
        const UrlSet.union([
          UrlSet.outbox('p1'),
          UrlSet.inbox('p2'),
          UrlSet.inbox('p3'),
          UrlSet.explicit(['wss://x']),
        ]),
        lists.fn,
      );
      expect(resolvedUrls(r), ['wss://w', 'wss://r', 'wss://x']);
    });

    test(
      'union is unavailable if any lookup is, with the urls found',
      () async {
        final lists = FakeUrlLists()
          ..set(
            'p1',
            UrlListKind.outbox,
            const UrlListLookup.found(['wss://w']),
          )
          ..set(
            'p3',
            UrlListKind.inbox,
            const UrlListLookup.found(['wss://r']),
          );
        final r = await resolveUrlSet(
          const UrlSet.union([
            UrlSet.outbox('p1'),
            UrlSet.dm('p2'),
            UrlSet.inbox('p3'),
            UrlSet.inbox('p4'),
          ]),
          lists.fn,
        );
        expect(r, isA<UrlsUnavailable>());
        final unavailable = r as UrlsUnavailable;
        expect(unavailable.lists, [
          const UnavailableUrlList('p2', UrlListKind.dm, 'offline'),
          const UnavailableUrlList('p4', UrlListKind.inbox, 'offline'),
        ]);
        expect(unavailable.urls, ['wss://w', 'wss://r']);
        expect(
          unavailable.reason,
          'dm list of p2 unavailable: offline; '
          'inbox list of p4 unavailable: offline',
        );
      },
    );

    test('first keeps the first urls of its set', () async {
      final lists = FakeUrlLists()
        ..set(
          'p1',
          UrlListKind.inbox,
          const UrlListLookup.found(['wss://a', 'wss://b', 'wss://c']),
        );
      Future<UrlResolution> first(int count) => resolveUrlSet(
        UrlSet.first(count, const UrlSet.inbox('p1')),
        lists.fn,
      );

      expect(resolvedUrls(await first(2)), ['wss://a', 'wss://b']);
      expect(resolvedUrls(await first(5)), ['wss://a', 'wss://b', 'wss://c']);
      expect(resolvedUrls(await first(0)), isEmpty);
    });

    test('first counts each url once, compared as written', () async {
      final lists = FakeUrlLists()
        ..set('p1', UrlListKind.outbox, const UrlListLookup.found(['wss://a']))
        ..set(
          'p2',
          UrlListKind.outbox,
          const UrlListLookup.found(['wss://a', 'wss://b', 'wss://a/']),
        );
      final r = await resolveUrlSet(
        const UrlSet.first(
          3,
          UrlSet.union([UrlSet.outbox('p1'), UrlSet.outbox('p2')]),
        ),
        lists.fn,
      );
      expect(r, const UrlsResolved(['wss://a', 'wss://b', 'wss://a/']));
    });

    test('first is unavailable when its set is', () async {
      final lists = FakeUrlLists()
        ..set(
          'p2',
          UrlListKind.inbox,
          const UrlListLookup.found(['wss://a', 'wss://b', 'wss://c']),
        );
      final r = await resolveUrlSet(
        const UrlSet.first(
          2,
          UrlSet.union([UrlSet.inbox('p1'), UrlSet.inbox('p2')]),
        ),
        lists.fn,
      );
      expect(r, isA<UrlsUnavailable>());
      expect((r as UrlsUnavailable).urls, ['wss://a', 'wss://b']);
    });

    test('first of none needs no lookup, even of an unavailable set', () async {
      final lists = FakeUrlLists();
      const set = UrlSet.first(0, UrlSet.inbox('p1'));

      expect(set.needsLookup, isFalse);
      expect(set.kinds, {UrlListKind.inbox});
      expect(resolvedUrls(await resolveUrlSet(set, lists.fn)), isEmpty);
      expect(lists.calls, isEmpty);
    });

    test('a fallback moves past a first of none', () async {
      final r = await resolveUrlSet(
        const UrlSet.fallback([
          UrlSet.first(0, UrlSet.outbox('p1')),
          UrlSet.explicit(['wss://default']),
        ]),
        FakeUrlLists().fn,
      );
      expect(resolvedUrls(r), ['wss://default']);
    });

    test('nip65 looks up every relay of the list', () async {
      final lists = FakeUrlLists()
        ..set(
          'p',
          UrlListKind.nip65,
          const UrlListLookup.found(['wss://r', 'wss://w']),
        );
      final r = await resolveUrlSet(const UrlSet.nip65('p'), lists.fn);
      expect(resolvedUrls(r), ['wss://r', 'wss://w']);
      expect(lists.calls, ['nip65|p']);
    });

    test('looks up DM, private and Blossom lists alone', () async {
      final lists = FakeUrlLists()
        ..set('p', UrlListKind.dm, const UrlListLookup.found(['wss://dm']))
        ..set('p', UrlListKind.private, const UrlListLookup.found(['wss://s']))
        ..set(
          'p',
          UrlListKind.blossom,
          const UrlListLookup.found(['https://cdn.example']),
        );
      final r = await resolveUrlSet(
        const UrlSet.union([
          UrlSet.dm('p'),
          UrlSet.private('p'),
          UrlSet.blossom('p'),
        ]),
        lists.fn,
      );
      expect(
        r,
        const UrlsResolved(['wss://dm', 'wss://s', 'https://cdn.example']),
      );
      expect(lists.calls, ['dm|p', 'private|p', 'blossom|p']);
    });

    test('fallback skips empty and notFound sets', () async {
      final lists = FakeUrlLists()
        ..set('p1', UrlListKind.outbox, const UrlListLookup.notFound())
        ..set('p2', UrlListKind.outbox, const UrlListLookup.found([]))
        ..set('p3', UrlListKind.outbox, const UrlListLookup.found(['wss://c']));
      final r = await resolveUrlSet(
        const UrlSet.fallback([
          UrlSet.outbox('p1'),
          UrlSet.outbox('p2'),
          UrlSet.outbox('p3'),
          UrlSet.outbox('p4'),
        ]),
        lists.fn,
      );
      expect(resolvedUrls(r), ['wss://c']);
      expect(lists.calls, isNot(contains('outbox|p4')));
    });

    test('fallback to defaults when there is no Blossom list', () async {
      final lists = FakeUrlLists()
        ..set('p', UrlListKind.blossom, const UrlListLookup.notFound());
      final r = await resolveUrlSet(
        const UrlSet.fallback([
          UrlSet.blossom('p'),
          UrlSet.explicit(['https://default.example']),
        ]),
        lists.fn,
      );
      expect(resolvedUrls(r), ['https://default.example']);
    });

    test(
      'fallback stops on an unavailable set instead of falling through',
      () async {
        final lists = FakeUrlLists();
        final r = await resolveUrlSet(
          const UrlSet.fallback([
            UrlSet.outbox('p1'),
            UrlSet.explicit(['wss://local']),
          ]),
          lists.fn,
        );
        expect(r, isA<UrlsUnavailable>());
        expect((r as UrlsUnavailable).urls, isEmpty);
      },
    );

    test('looks up each pubkey and kind once', () async {
      final lists = FakeUrlLists()
        ..set('p1', UrlListKind.outbox, const UrlListLookup.found(['wss://a']))
        ..set('p1', UrlListKind.inbox, const UrlListLookup.found(['wss://b']));
      await resolveUrlSet(
        const UrlSet.union([
          UrlSet.outbox('p1'),
          UrlSet.outbox('p1'),
          UrlSet.inbox('p1'),
          UrlSet.inbox('p1'),
        ]),
        lists.fn,
      );
      expect(lists.calls, ['outbox|p1', 'inbox|p1']);
    });
  });

  group('results', () {
    const unavailable = UnavailableUrlList('p', UrlListKind.dm, 'offline');

    test('lookups, resolutions and snapshots compare by value', () {
      expect(UrlListFound(['wss://a']), UrlListFound(['wss://a']));
      expect(UrlListFound(['wss://a']), isNot(UrlListFound(['wss://b'])));
      expect(UrlListNotFound(), UrlListNotFound());
      expect(UrlListUnavailable('x'), UrlListUnavailable('x'));
      expect(UrlListUnavailable('x'), isNot(UrlListUnavailable()));
      expect(UrlsResolved(['wss://a']), UrlsResolved(['wss://a']));
      expect(
        UrlsResolved(['wss://a']).hashCode,
        UrlsResolved(['wss://a']).hashCode,
      );
      expect(UrlsResolved(['wss://a']), isNot(UrlsResolved(['wss://b'])));
      expect(
        UrlsUnavailable([unavailable], urls: ['wss://a']),
        UrlsUnavailable([unavailable], urls: ['wss://a']),
      );
      expect(
        UrlsUnavailable([unavailable]),
        isNot(UrlsUnavailable([unavailable], urls: ['wss://a'])),
      );
      expect(UrlsResolved([]), isNot(UrlsUnavailable([])));
      expect(
        UrlSetSnapshot(
          urls: ['wss://a'],
          unavailable: [unavailable],
          done: true,
        ),
        UrlSetSnapshot(
          urls: ['wss://a'],
          unavailable: [unavailable],
          done: true,
        ),
      );
      expect(
        UrlSetSnapshot(urls: ['wss://a'], done: true),
        isNot(UrlSetSnapshot(urls: ['wss://a'], done: false)),
      );
    });

    test('toString shows what they hold', () {
      expect(UrlListFound(['wss://a']).toString(), 'UrlListFound([wss://a])');
      expect(UrlListNotFound().toString(), 'UrlListNotFound()');
      expect(
        UrlListUnavailable('offline').toString(),
        'UrlListUnavailable(offline)',
      );
      expect(UrlListUnavailable().toString(), 'UrlListUnavailable()');
      expect(UrlsResolved(['wss://a']).toString(), 'UrlsResolved([wss://a])');
      expect(
        UrlsUnavailable([unavailable], urls: ['wss://a']).toString(),
        'UrlsUnavailable([dm list of p unavailable: offline], urls: [wss://a])',
      );
      expect(
        UrlSetSnapshot(
          urls: ['wss://a'],
          unavailable: [unavailable],
          done: true,
        ).toString(),
        'UrlSetSnapshot(urls: [wss://a], '
        'unavailable: [dm list of p unavailable: offline], done: true)',
      );
    });
  });
}
