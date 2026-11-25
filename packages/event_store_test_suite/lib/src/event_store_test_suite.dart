import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dostr_event_store/dostr_event_store.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:test/test.dart';

final _alice = 'a' * 64;
final _bob = 'b' * 64;
final _carol = 'c' * 64;
final _sig = 'e' * 128;

/// Runs the contract every [EventStore] must keep against one
/// implementation: the NIP-01, NIP-09, NIP-59 and NIP-40 rules that
/// [EventStore] lists, the order and limits of [EventStore.query], what
/// [EventStore.remove] removes, and the [StateError] once it is closed.
///
/// [createStore] returns an empty store for each test, which the suite closes
/// once the test ends.
///
/// ```dart
/// runEventStoreTestSuite(
///   name: 'SqliteEventStore',
///   createStore: () => SqliteEventStore.inMemory(),
/// );
/// ```
void runEventStoreTestSuite({
  required String name,
  required FutureOr<EventStore> Function() createStore,
}) {
  group(name, () {
    late EventStore store;

    setUp(() async => store = await createStore());
    tearDown(() => store.close());

    Nip01Event event({
      String? pubkey,
      int kind = 1,
      int createdAt = 1000,
      List<List<String>> tags = const [],
      String content = '',
    }) => Nip01Event(
      pubkey: pubkey ?? _alice,
      kind: kind,
      createdAt: createdAt,
      tags: tags,
      content: content,
      sig: _sig,
    );

    Nip01Event deletion({
      String? pubkey,
      List<String> ids = const [],
      List<String> addresses = const [],
      int createdAt = 2000,
      List<List<String>> tags = const [],
    }) => event(
      pubkey: pubkey,
      kind: 5,
      createdAt: createdAt,
      tags: [
        for (final id in ids) ['e', id],
        for (final address in addresses) ['a', address],
        ...tags,
      ],
    );

    Future<void> addEach(List<Nip01Event> events) async {
      for (final event in events) {
        await store.add(event);
      }
    }

    Future<List<String>> idsOf(List<Filter> filters) async => [
      for (final event in await store.query(filters)) event.id,
    ];

    Future<List<String>> allIds() => idsOf([Filter()]);

    Future<T> at<T>(int seconds, Future<T> Function() body) => withClock(
      Clock.fixed(
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
      ),
      body,
    );

    group('add', () {
      test('stores an event and gives it back as it was added', () async {
        final note = event(
          tags: [
            ['p', _bob],
            ['t', 'nostr', 'extra'],
          ],
          content: 'hello "world"\n✨',
        );

        expect(await store.add(note), EventAddOutcome.stored);

        final found = await store.query([
          Filter(ids: [note.id]),
        ]);
        expect(found.map((event) => event.toJson()), [note.toJson()]);
      });

      test('tells an event that is already stored', () async {
        final note = event();
        await store.add(note);

        expect(await store.add(note), EventAddOutcome.duplicate);
        expect(await allIds(), [note.id]);
      });

      test('does not store an ephemeral event', () async {
        expect(await store.add(event(kind: 20001)), EventAddOutcome.ephemeral);
        expect(await allIds(), isEmpty);
      });
    });

    group('query', () {
      test('matches ids, authors and kinds', () async {
        final aliceNote = event(content: 'alice');
        final bobNote = event(pubkey: _bob, content: 'bob');
        final aliceReaction = event(kind: 7, content: '+');
        await addEach([aliceNote, bobNote, aliceReaction]);

        expect(
          await idsOf([
            Filter(ids: [bobNote.id, aliceReaction.id]),
          ]),
          unorderedEquals([bobNote.id, aliceReaction.id]),
        );
        expect(
          await idsOf([
            Filter(authors: [_alice]),
          ]),
          unorderedEquals([aliceNote.id, aliceReaction.id]),
        );
        expect(
          await idsOf([
            Filter(kinds: [1]),
          ]),
          unorderedEquals([aliceNote.id, bobNote.id]),
        );
        expect(
          await idsOf([
            Filter(authors: [_alice], kinds: [1]),
          ]),
          [aliceNote.id],
        );
      });

      test('matches a tag filter against the value of each tag', () async {
        final reply = event(
          tags: [
            ['e', 'root'],
            ['p', _bob],
            ['p', _carol],
          ],
        );
        await store.add(reply);

        expect(
          await idsOf([
            Filter(
              tags: {
                'p': [_carol],
              },
            ),
          ]),
          [reply.id],
        );
        expect(
          await idsOf([
            Filter(eTags: ['root'], pTags: [_bob]),
          ]),
          [reply.id],
        );
        expect(
          await idsOf([
            Filter(eTags: [_bob]),
          ]),
          isEmpty,
        );
        expect(
          await idsOf([
            Filter(
              tags: {
                't': ['root'],
              },
            ),
          ]),
          isEmpty,
        );
      });

      test('bounds created_at with since and until, both included', () async {
        final notes = [
          for (final createdAt in [10, 20, 30, 40]) event(createdAt: createdAt),
        ];
        await addEach(notes);

        expect(await idsOf([Filter(since: 20, until: 30)]), [
          notes[2].id,
          notes[1].id,
        ]);
      });

      test('gives the matches of every filter once, newest first', () async {
        final notes = [
          for (final createdAt in [10, 30, 20]) event(createdAt: createdAt),
        ];
        await addEach(notes);

        expect(
          await idsOf([
            Filter(ids: [notes[0].id, notes[1].id]),
            Filter(ids: [notes[1].id, notes[2].id]),
          ]),
          [notes[1].id, notes[2].id, notes[0].id],
        );
      });

      test('orders the events of the same created_at by id', () async {
        final notes = [for (var i = 0; i < 5; i++) event(content: '$i')];
        await addEach(notes);

        final ids = [for (final note in notes) note.id]..sort();
        expect(await allIds(), ids);
      });

      test('keeps the newest limit matches of each filter', () async {
        final aliceNotes = [
          for (var createdAt = 1; createdAt <= 4; createdAt++)
            event(createdAt: createdAt),
        ];
        final bobNotes = [
          for (var createdAt = 11; createdAt <= 13; createdAt++)
            event(pubkey: _bob, createdAt: createdAt),
        ];
        await addEach([...aliceNotes, ...bobNotes]);

        expect(
          await idsOf([
            Filter(authors: [_alice], limit: 2),
            Filter(authors: [_bob], limit: 1),
          ]),
          [bobNotes[2].id, aliceNotes[3].id, aliceNotes[2].id],
        );
      });

      test('keeps the lower ids when a limit cuts a created_at', () async {
        final notes = [for (var i = 0; i < 4; i++) event(content: '$i')];
        await addEach(notes);

        final ids = [for (final note in notes) note.id]..sort();
        expect(await idsOf([Filter(limit: 2)]), ids.take(2));
      });

      test('matches every event with an empty filter', () async {
        final notes = [event(content: '1'), event(kind: 7, pubkey: _bob)];
        await addEach(notes);

        expect(
          await allIds(),
          unorderedEquals([for (final note in notes) note.id]),
        );
      });

      test(
        'matches nothing without a filter, with an empty list, or a limit of 0',
        () async {
          await store.add(event());

          expect(await idsOf([]), isEmpty);
          expect(await idsOf([Filter(authors: [])]), isEmpty);
          expect(
            await idsOf([
              Filter(tags: {'p': []}),
            ]),
            isEmpty,
          );
          expect(await idsOf([Filter(limit: 0)]), isEmpty);
        },
      );
    });

    group('NIP-01 replaceable events', () {
      test('a newer version replaces the older one', () async {
        final older = event(kind: 0, createdAt: 1000);
        final newer = event(kind: 0, createdAt: 1001);

        expect(await store.add(older), EventAddOutcome.stored);
        expect(await store.add(newer), EventAddOutcome.stored);
        expect(await allIds(), [newer.id]);
      });

      test('an older version is outdated', () async {
        final older = event(kind: 0, createdAt: 1000);
        final newer = event(kind: 0, createdAt: 1001);
        await store.add(newer);

        expect(await store.add(older), EventAddOutcome.outdated);
        expect(await allIds(), [newer.id]);
      });

      test('at the same created_at, the lower id wins', () async {
        final versions = [
          event(kind: 0, content: 'one'),
          event(kind: 0, content: 'two'),
        ]..sort((a, b) => a.id.compareTo(b.id));
        final [lower, higher] = versions;

        expect(await store.add(higher), EventAddOutcome.stored);
        expect(await store.add(lower), EventAddOutcome.stored);
        expect(await store.add(higher), EventAddOutcome.outdated);
        expect(await allIds(), [lower.id]);
      });

      test('kinds 3 and 10000 to 19999 are replaceable too', () async {
        for (final kind in [3, 10000, 10002, 19999]) {
          await store.add(event(kind: kind, createdAt: 1000));
          await store.add(event(kind: kind, createdAt: 1001));
        }

        final found = await store.query([Filter()]);
        expect(
          found.map((event) => event.kind),
          unorderedEquals([3, 10000, 10002, 19999]),
        );
        expect(found.map((event) => event.createdAt), everyElement(1001));
      });

      test('each author has its own version', () async {
        final alice = event(kind: 0, createdAt: 1000);
        final bob = event(kind: 0, pubkey: _bob, createdAt: 1001);
        await addEach([alice, bob]);

        expect(await allIds(), [bob.id, alice.id]);
      });

      test('an addressable event is replaced per d tag', () async {
        Nip01Event article(String d, int createdAt) => event(
          kind: 30023,
          createdAt: createdAt,
          tags: [
            ['d', d],
          ],
        );
        final first = article('first', 1000);
        final second = article('second', 1001);
        final firstEdited = article('first', 1002);
        await addEach([first, second, firstEdited]);

        expect(await allIds(), [firstEdited.id, second.id]);
      });

      test('an addressable event without a d tag has an empty one', () async {
        final untagged = event(kind: 30000, createdAt: 1000);
        final empty = event(
          kind: 30000,
          createdAt: 1001,
          tags: [
            ['d', ''],
          ],
        );
        await addEach([untagged, empty]);

        expect(await allIds(), [empty.id]);
      });

      test('regular events are all kept', () async {
        final notes = [event(createdAt: 1000), event(createdAt: 1001)];
        await addEach(notes);

        expect(await allIds(), [notes[1].id, notes[0].id]);
      });
    });

    group('NIP-09 deletion requests', () {
      test('remove the events their e tags name, of their author', () async {
        final deleted = event(content: 'deleted');
        final kept = event(content: 'kept');
        await addEach([deleted, kept]);
        final request = deletion(ids: [deleted.id]);

        expect(await store.add(request), EventAddOutcome.stored);
        expect(await allIds(), [request.id, kept.id]);
      });

      test('leave the events of another author', () async {
        final bobNote = event(pubkey: _bob);
        await store.add(bobNote);
        await store.add(deletion(ids: [bobNote.id]));

        expect(
          await idsOf([
            Filter(ids: [bobNote.id]),
          ]),
          [bobNote.id],
        );
      });

      test('refuse the events they removed', () async {
        final note = event();
        await store.add(note);
        await store.add(deletion(ids: [note.id]));

        expect(await store.add(note), EventAddOutcome.deleted);
      });

      test('refuse the events they name that come after them', () async {
        final note = event();
        await store.add(deletion(ids: [note.id]));

        expect(await store.add(note), EventAddOutcome.deleted);
        expect(
          await idsOf([
            Filter(ids: [note.id]),
          ]),
          isEmpty,
        );
      });

      test(
        'remove the versions of an address up to their created_at',
        () async {
          Nip01Event article(int createdAt) => event(
            kind: 30023,
            createdAt: createdAt,
            tags: [
              ['d', 'post'],
            ],
          );
          await store.add(article(1000));
          final request = deletion(
            addresses: ['30023:$_alice:post'],
            createdAt: 1500,
          );

          expect(await store.add(request), EventAddOutcome.stored);
          expect(await allIds(), [request.id]);
          expect(await store.add(article(1200)), EventAddOutcome.deleted);
          expect(await store.add(article(1500)), EventAddOutcome.deleted);
          expect(await store.add(article(1501)), EventAddOutcome.stored);
        },
      );

      test('name a replaceable kind by its address with an empty d', () async {
        final relays = event(kind: 10002, createdAt: 1000);
        await store.add(relays);
        await store.add(
          deletion(addresses: ['10002:$_alice:'], createdAt: 1500),
        );

        expect(
          await idsOf([
            Filter(kinds: [10002]),
          ]),
          isEmpty,
        );
        expect(await store.add(relays), EventAddOutcome.deleted);
      });

      test('leave an address of another author', () async {
        final article = event(
          kind: 30023,
          tags: [
            ['d', 'post'],
          ],
        );
        await store.add(article);
        await store.add(
          deletion(pubkey: _bob, addresses: ['30023:$_alice:post']),
        );

        expect(
          await idsOf([
            Filter(kinds: [30023]),
          ]),
          [article.id],
        );
      });

      test('do not delete another deletion request', () async {
        final first = deletion(ids: ['f' * 64]);
        await store.add(first);
        await store.add(deletion(ids: [first.id], createdAt: 2001));

        expect(
          await idsOf([
            Filter(ids: [first.id]),
          ]),
          [first.id],
        );
      });

      test('once removed, let the events they named in again', () async {
        final note = event();
        final request = deletion(ids: [note.id]);
        await addEach([note, request]);

        expect(
          await store.remove([
            Filter(ids: [request.id]),
          ]),
          1,
        );
        expect(await store.add(note), EventAddOutcome.stored);
      });
    });

    group('NIP-59 gift wraps', () {
      Nip01Event wrapFor(String recipient) => event(
        pubkey: _carol,
        kind: 1059,
        tags: [
          ['p', recipient],
        ],
        content: 'sealed',
      );

      test('their recipient deletes them', () async {
        final wrap = wrapFor(_bob);
        await store.add(wrap);
        await store.add(deletion(pubkey: _bob, ids: [wrap.id]));

        expect(
          await idsOf([
            Filter(kinds: [1059]),
          ]),
          isEmpty,
        );
        expect(await store.add(wrap), EventAddOutcome.deleted);
      });

      test('a deletion of their recipient refuses them', () async {
        final wrap = wrapFor(_bob);
        await store.add(deletion(pubkey: _bob, ids: [wrap.id]));

        expect(await store.add(wrap), EventAddOutcome.deleted);
      });

      test('their author deletes them', () async {
        final wrap = wrapFor(_bob);
        await store.add(wrap);
        await store.add(deletion(pubkey: _carol, ids: [wrap.id]));

        expect(
          await idsOf([
            Filter(kinds: [1059]),
          ]),
          isEmpty,
        );
      });

      test('another pubkey cannot delete them', () async {
        final wrap = wrapFor(_bob);
        await store.add(wrap);
        await store.add(deletion(pubkey: _alice, ids: [wrap.id]));

        expect(
          await idsOf([
            Filter(kinds: [1059]),
          ]),
          [wrap.id],
        );
      });

      test('the pubkey a note refers to cannot delete it', () async {
        final note = event(
          pubkey: _carol,
          tags: [
            ['p', _bob],
          ],
        );
        await store.add(note);
        await store.add(deletion(pubkey: _bob, ids: [note.id]));

        expect(
          await idsOf([
            Filter(ids: [note.id]),
          ]),
          [note.id],
        );
      });
    });

    group('NIP-40 expiration', () {
      Nip01Event expiring(String expiration, {int kind = 1}) => event(
        kind: kind,
        tags: [
          ['expiration', expiration],
        ],
      );

      test('refuses an event from its expiration on', () async {
        expect(
          await at(2000, () => store.add(expiring('1999'))),
          EventAddOutcome.expired,
        );
        expect(
          await at(2000, () => store.add(expiring('2000'))),
          EventAddOutcome.expired,
        );
        expect(
          await at(2000, () => store.add(expiring('2001'))),
          EventAddOutcome.stored,
        );
      });

      test('stops giving a stored event once it expires', () async {
        final note = expiring('1500');
        await at(1000, () => store.add(note));

        expect(await at(1499, allIds), [note.id]);
        expect(await at(1500, allIds), isEmpty);
        expect(await at(1500, () => store.remove([Filter()])), 0);
      });

      test('keeps an event whose expiration is not a number', () async {
        final note = expiring('soon');

        expect(await store.add(note), EventAddOutcome.stored);
        expect(await allIds(), [note.id]);
      });

      test(
        'an expired deletion request no longer refuses what it named',
        () async {
          final note = event(content: 'note');
          final request = event(
            kind: 5,
            createdAt: 2000,
            tags: [
              ['e', note.id],
              ['expiration', '1500'],
            ],
          );
          await at(1000, () => addEach([note, request]));

          expect(
            await at(1499, () => store.add(note)),
            EventAddOutcome.deleted,
          );
          expect(await at(1500, () => store.add(note)), EventAddOutcome.stored);
        },
      );

      test('an expired version gives way to an older one', () async {
        final newer = event(
          kind: 0,
          createdAt: 1001,
          tags: [
            ['expiration', '1500'],
          ],
        );
        final older = event(kind: 0, createdAt: 1000);
        await at(1000, () => store.add(newer));

        expect(await at(1500, () => store.add(older)), EventAddOutcome.stored);
        expect(await at(1500, allIds), [older.id]);
      });
    });

    group('remove', () {
      test('removes what query gives and tells how many', () async {
        final aliceNotes = [event(content: '1'), event(content: '2')];
        final bobNote = event(pubkey: _bob);
        await addEach([...aliceNotes, bobNote]);

        expect(
          await store.remove([
            Filter(authors: [_alice]),
          ]),
          2,
        );
        expect(await allIds(), [bobNote.id]);
      });

      test('keeps to the limit of each filter', () async {
        final notes = [
          for (var createdAt = 1; createdAt <= 3; createdAt++)
            event(createdAt: createdAt),
        ];
        await addEach(notes);

        expect(await store.remove([Filter(limit: 1)]), 1);
        expect(await allIds(), [notes[1].id, notes[0].id]);
      });

      test('lets an older version in once the newer one is gone', () async {
        final older = event(kind: 0, createdAt: 1000);
        final newer = event(kind: 0, createdAt: 1001);
        await store.add(newer);
        await store.remove([
          Filter(ids: [newer.id]),
        ]);

        expect(await store.add(older), EventAddOutcome.stored);
      });
    });

    group('close', () {
      test('makes every other method throw a StateError', () async {
        await store.close();

        await expectLater(() => store.add(event()), throwsStateError);
        await expectLater(() => store.query([Filter()]), throwsStateError);
        await expectLater(() => store.remove([Filter()]), throwsStateError);
      });

      test('can be called again', () async {
        await store.close();

        await expectLater(store.close(), completes);
      });
    });
  });
}
