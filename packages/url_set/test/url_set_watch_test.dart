import 'dart:async';

import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

class FakeUrlListWatches {
  final Map<String, StreamController<UrlListLookup>> lists = {};
  final Map<String, Future<List<String>>> outboxRelays = {};
  final List<String> calls = [];
  final Set<String> cancelled = {};

  UrlListWatchFn get fn => (pubkey, kind, outboxRelays) {
    final id = '${kind.name}|$pubkey';
    calls.add(id);
    this.outboxRelays[id] = outboxRelays;
    final list = lists[id] = StreamController(
      onCancel: () => cancelled.add(id),
    );
    return list.stream;
  };

  Future<void> answer(String id, UrlListLookup lookup) async {
    lists[id]!.add(lookup);
    await pumpEventQueue();
  }

  Future<void> end(String id) async {
    await lists[id]!.close();
    await pumpEventQueue();
  }
}

class Watching {
  final List<UrlSetSnapshot> snapshots = [];
  final List<Object> errors = [];
  bool closed = false;
  late final StreamSubscription<UrlSetSnapshot> subscription;

  Watching(Stream<UrlSetSnapshot> stream) {
    subscription = stream.listen(
      snapshots.add,
      onError: errors.add,
      onDone: () => closed = true,
    );
  }

  List<List<String>> get urls => [for (final s in snapshots) s.urls];
  List<bool> get done => [for (final s in snapshots) s.done];
  UrlSetSnapshot get last => snapshots.last;
}

Future<Watching> watching(UrlSet set, FakeUrlListWatches lists) async {
  final watching = Watching(watchUrlSet(set, lists.fn));
  await pumpEventQueue();
  return watching;
}

void main() {
  group('watchUrlSet', () {
    test('resolves explicit urls without a lookup', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(const UrlSet.explicit(['wss://x']), lists);
      expect(w.urls, [
        ['wss://x'],
      ]);
      expect(w.done, [true]);
      expect(w.closed, isTrue);
      expect(lists.calls, isEmpty);
    });

    test('watches nothing before it is listened to', () async {
      final lists = FakeUrlListWatches();
      watchUrlSet(const UrlSet.outbox('p'), lists.fn);
      await pumpEventQueue();
      expect(lists.calls, isEmpty);
    });

    test('a union gives each list as it arrives', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.union([
          UrlSet.explicit(['wss://x']),
          UrlSet.outbox('p1'),
          UrlSet.outbox('p2'),
        ]),
        lists,
      );
      expect(w.urls, [
        ['wss://x'],
      ]);

      await lists.answer('outbox|p2', const UrlListLookup.found(['wss://b']));
      await lists.answer('outbox|p1', const UrlListLookup.found(['wss://a']));
      await lists.end('outbox|p1');
      expect(w.closed, isFalse);
      await lists.end('outbox|p2');

      expect(w.urls, [
        ['wss://x'],
        ['wss://x', 'wss://b'],
        ['wss://x', 'wss://a', 'wss://b'],
        ['wss://x', 'wss://a', 'wss://b'],
      ]);
      expect(w.done, [false, false, false, true]);
      expect(w.closed, isTrue);
      expect((w.last.resolution as UrlsResolved).urls, [
        'wss://x',
        'wss://a',
        'wss://b',
      ]);
    });

    test('a newer version of a list replaces the one before', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(const UrlSet.outbox('p'), lists);
      await lists.answer('outbox|p', const UrlListLookup.found(['wss://a']));
      await lists.answer('outbox|p', const UrlListLookup.found(['wss://b']));
      await lists.end('outbox|p');
      expect(w.urls, [
        <String>[],
        ['wss://a'],
        ['wss://b'],
        ['wss://b'],
      ]);
      expect(w.done.last, isTrue);
    });

    test('a list that ends without an answer is unavailable', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(const UrlSet.outbox('p'), lists);
      await lists.end('outbox|p');
      expect(w.last.done, isTrue);
      expect(w.last.unavailable, ['outbox list of p unavailable']);
    });

    test('a not found list ends before its stream does', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(const UrlSet.outbox('p'), lists);
      await lists.answer('outbox|p', const UrlListLookup.notFound());
      expect(w.last.done, isTrue);
      expect(w.last.urls, isEmpty);
      expect(w.closed, isTrue);
      expect(lists.cancelled, {'outbox|p'});
    });

    test('a union keeps the urls of the lists available', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.union([UrlSet.outbox('p1'), UrlSet.outbox('p2')]),
        lists,
      );
      await lists.answer(
        'outbox|p1',
        const UrlListLookup.unavailable('offline'),
      );
      await lists.answer('outbox|p2', const UrlListLookup.found(['wss://b']));
      await lists.end('outbox|p2');
      expect(w.last.done, isTrue);
      expect(w.last.urls, ['wss://b']);
      expect(w.last.unavailable, ['outbox list of p1 unavailable: offline']);
      expect(
        (w.last.resolution as UrlsUnavailable).reason,
        'outbox list of p1 unavailable: offline',
      );
    });

    test('a fallback waits for a set to end empty before the next', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.fallback([
          UrlSet.outbox('p'),
          UrlSet.explicit(['wss://d']),
        ]),
        lists,
      );
      expect(w.urls, [<String>[]]);
      await lists.answer('outbox|p', const UrlListLookup.notFound());
      expect(w.urls, [
        <String>[],
        ['wss://d'],
      ]);
      expect(w.done, [false, true]);
    });

    test('a fallback stops on an unavailable set', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.fallback([UrlSet.outbox('p1'), UrlSet.outbox('p2')]),
        lists,
      );
      await lists.answer(
        'outbox|p1',
        const UrlListLookup.unavailable('offline'),
      );
      expect(w.last.done, isTrue);
      expect(w.last.resolution, isA<UrlsUnavailable>());
      expect(lists.calls, ['outbox|p1']);
    });

    test('a fallback moves on when a newer version is empty', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.fallback([
          UrlSet.outbox('p'),
          UrlSet.explicit(['wss://d']),
        ]),
        lists,
      );
      await lists.answer('outbox|p', const UrlListLookup.found(['wss://a']));
      await lists.answer('outbox|p', const UrlListLookup.found([]));
      await lists.end('outbox|p');
      expect(w.urls, [
        <String>[],
        ['wss://a'],
        <String>[],
        ['wss://d'],
      ]);
      expect(w.done.last, isTrue);
    });

    test('a fallback does not watch the sets after a non-empty one', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.fallback([UrlSet.outbox('p1'), UrlSet.outbox('p2')]),
        lists,
      );
      await lists.answer('outbox|p1', const UrlListLookup.found(['wss://a']));
      await lists.end('outbox|p1');
      expect(w.last.urls, ['wss://a']);
      expect(w.last.done, isTrue);
      expect(lists.calls, ['outbox|p1']);
    });

    test('first keeps the first urls known so far', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.first(
          1,
          UrlSet.union([UrlSet.inbox('p1'), UrlSet.inbox('p2')]),
        ),
        lists,
      );
      await lists.answer(
        'inbox|p2',
        const UrlListLookup.found(['wss://b', 'wss://c']),
      );
      await lists.answer('inbox|p1', const UrlListLookup.found(['wss://a']));
      await lists.end('inbox|p1');
      await lists.end('inbox|p2');
      expect(w.urls, [
        <String>[],
        ['wss://b'],
        ['wss://a'],
        ['wss://a'],
      ]);
      expect(w.done.last, isTrue);
    });

    test('first of none watches nothing', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(const UrlSet.first(0, UrlSet.inbox('p')), lists);
      expect(w.urls, [<String>[]]);
      expect(w.done, [true]);
      expect(lists.calls, isEmpty);
    });

    test('watches a DM list without waiting for the NIP-65', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(const UrlSet.dm('p'), lists);
      expect(lists.calls, ['outbox|p', 'dm|p']);

      await lists.answer('dm|p', const UrlListLookup.found(['wss://dm']));
      await lists.end('dm|p');
      expect(w.last.urls, ['wss://dm']);
      expect(w.last.done, isFalse);

      await lists.answer('outbox|p', const UrlListLookup.found(['wss://w']));
      await lists.end('outbox|p');
      expect(w.last.urls, ['wss://dm']);
      expect(w.last.done, isTrue);
      expect(await lists.outboxRelays['dm|p'], ['wss://w']);
      expect(await lists.outboxRelays['outbox|p'], isEmpty);
    });

    test('a DM list not found waits for the NIP-65', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(const UrlSet.dm('p'), lists);
      await lists.answer('dm|p', const UrlListLookup.notFound());
      expect(w.last.done, isFalse);
      await lists.answer('outbox|p', const UrlListLookup.notFound());
      expect(w.last.urls, isEmpty);
      expect(w.last.done, isTrue);
      expect(await lists.outboxRelays['dm|p'], isEmpty);
    });

    test(
      'DM relays are unavailable while NIP-65 is, with the urls found',
      () async {
        final lists = FakeUrlListWatches();
        final w = await watching(const UrlSet.dm('p'), lists);
        await lists.answer('dm|p', const UrlListLookup.found(['wss://dm']));
        await lists.end('dm|p');
        await lists.answer(
          'outbox|p',
          const UrlListLookup.unavailable('offline'),
        );
        expect(w.last.done, isTrue);
        expect(w.last.urls, ['wss://dm']);
        expect(w.last.unavailable, [
          'dm list of p unavailable: NIP-65 offline',
        ]);
      },
    );

    test('watches each pubkey and kind once', () async {
      final lists = FakeUrlListWatches();
      await watching(
        const UrlSet.union([
          UrlSet.outbox('p'),
          UrlSet.dm('p'),
          UrlSet.first(2, UrlSet.outbox('p')),
        ]),
        lists,
      );
      expect(lists.calls, ['outbox|p', 'dm|p']);
    });

    test('cancelling the stream cancels the lookups', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.union([UrlSet.outbox('p1'), UrlSet.inbox('p2')]),
        lists,
      );
      await w.subscription.cancel();
      expect(lists.cancelled, {'outbox|p1', 'inbox|p2'});
    });

    test('an error of a lookup ends the stream with it', () async {
      final lists = FakeUrlListWatches();
      final w = await watching(
        const UrlSet.union([UrlSet.outbox('p1'), UrlSet.inbox('p2')]),
        lists,
      );
      lists.lists['outbox|p1']!.addError(StateError('broken'));
      await pumpEventQueue();
      expect(w.errors, [isA<StateError>()]);
      expect(w.closed, isTrue);
      expect(lists.cancelled, contains('inbox|p2'));
    });

    test('ends as resolveUrlSet resolves the lists as they ended', () async {
      const set = UrlSet.union([
        UrlSet.fallback([
          UrlSet.dm('p1'),
          UrlSet.explicit(['wss://d']),
        ]),
        UrlSet.first(1, UrlSet.inbox('p2')),
        UrlSet.outbox('p3'),
      ]);
      const answers = {
        'outbox|p1': UrlListLookup.found(['wss://w1']),
        'dm|p1': UrlListLookup.notFound(),
        'inbox|p2': UrlListLookup.found(['wss://r1', 'wss://r2']),
        'outbox|p3': UrlListLookup.unavailable('offline'),
      };

      final lists = FakeUrlListWatches();
      final w = await watching(set, lists);
      for (final MapEntry(key: id, value: lookup) in answers.entries) {
        await lists.answer(id, lookup);
        await lists.end(id);
      }
      final resolved = await resolveUrlSet(
        set,
        (pubkey, kind, _) async => answers['${kind.name}|$pubkey']!,
      );

      expect(w.last.done, isTrue);
      expect(w.last.urls, ['wss://d', 'wss://r1']);
      expect(
        (w.last.resolution as UrlsUnavailable).reason,
        (resolved as UrlsUnavailable).reason,
      );
    });
  });
}
