import 'dart:convert';
import 'dart:io';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_fetchers/ndk_fetchers.dart';
import 'package:ndk_home_relays/ndk_home_relays.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:test/test.dart';

const alice =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const bob = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Nip01Event relayList(
  List<List<String>> tags, {
  String pubKey = alice,
  int createdAt = 1000,
  int kind = 10002,
}) => Nip01Event(
  pubKey: pubKey,
  kind: kind,
  tags: tags,
  content: '',
  createdAt: createdAt,
).copyWith(sig: 'f' * 128);

Nip01Event metadata(
  String name, {
  String pubKey = alice,
  int createdAt = 1000,
  int kind = 0,
}) => Nip01Event(
  pubKey: pubKey,
  kind: kind,
  tags: [],
  content: jsonEncode({'name': name}),
  createdAt: createdAt,
).copyWith(sig: 'f' * 128);

class AcceptAll implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async => true;
}

/// Keeps the last event saved per kind, pubkey and d tag.
class MemoryCache implements ReplaceableEventCache {
  final Map<String, Nip01Event> events = {};

  static String _key(int kind, String pubKey, String? dTag) =>
      '$kind|$pubKey|${dTag ?? ''}';

  @override
  Future<Nip01Event?> load({
    required int kind,
    required String pubKey,
    String? dTag,
  }) async => events[_key(kind, pubKey, dTag)];

  @override
  Future<void> save(Nip01Event event) async =>
      events[_key(event.kind, event.pubKey, event.dTag)] = event;
}

/// Answers every REQ with all its [events], whatever the filter, then EOSE.
class LocalRelay {
  final List<Nip01Event> events;
  late final HttpServer _server;
  int reqCount = 0;

  LocalRelay(this.events);

  String get url => 'ws://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((data) {
        final message = jsonDecode(data as String) as List;
        if (message[0] != 'REQ') return;
        reqCount++;
        final id = message[1];
        for (final event in events) {
          socket.add(jsonEncode(['EVENT', id, event.toJson()]));
        }
        socket.add(jsonEncode(['EOSE', id]));
      });
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late RelayManager relayManager;
  late RelayReqs reqs;
  final relays = <LocalRelay>[];

  Future<String> startRelay(List<Nip01Event> events) async {
    final relay = LocalRelay(events);
    await relay.start();
    relays.add(relay);
    return relay.url;
  }

  /// A relay that accepts the connection and never answers.
  Future<String> startSilentRelay() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.transform(WebSocketTransformer()).listen((_) {});
    addTearDown(() => server.close(force: true));
    return 'ws://127.0.0.1:${server.port}';
  }

  Future<LocalRelay> startCountedRelay(List<Nip01Event> events) async {
    final relay = LocalRelay(events);
    await relay.start();
    relays.add(relay);
    return relay;
  }

  setUp(() {
    relayManager = RelayManager(
      nostrTransportFactory: WebSocketClientNostrTransportFactory(
        pingInterval: null,
      ),
    );
    reqs = RelayReqs(relayManager: relayManager, eventVerifier: AcceptAll());
  });

  tearDown(() async {
    await relayManager.closeAllTransports();
    await Future.wait(relays.map((relay) => relay.stop()));
    relays.clear();
  });

  test('writeRelaysOf keeps the r tags not marked read, each once', () {
    final list = relayList([
      ['r', 'wss://both.example.com/'],
      ['r', 'wss://write.example.com', 'write'],
      ['r', 'wss://read.example.com', 'read'],
      ['r', 'wss://Both.example.com'],
      ['relay', 'wss://other.example.com'],
    ]);

    expect(writeRelaysOf(list), [
      'wss://both.example.com',
      'wss://write.example.com',
    ]);
  });

  test('readRelaysOf keeps the r tags not marked write, allRelaysOf all', () {
    final list = relayList([
      ['r', 'wss://both.example.com/'],
      ['r', 'wss://write.example.com', 'write'],
      ['r', 'wss://read.example.com', 'read'],
      ['r', 'wss://Both.example.com'],
      ['relay', 'wss://other.example.com'],
    ]);

    expect(readRelaysOf(list), [
      'wss://both.example.com',
      'wss://read.example.com',
    ]);
    expect(allRelaysOf(list), [
      'wss://both.example.com',
      'wss://write.example.com',
      'wss://read.example.com',
    ]);
  });

  group('Nip65Fetcher', () {
    test('keeps the newest list across relays', () async {
      final old = relayList([
        ['r', 'wss://old.example.com'],
      ], createdAt: 1000);
      final current = relayList([
        ['r', 'wss://new.example.com'],
      ], createdAt: 2000);
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [
          await startRelay([old]),
          await startRelay([current]),
        ],
      );

      expect((await fetcher.fetch(alice))?.id, current.id);
    });

    test('keeps the lowest id on a tie', () async {
      final first = relayList([
        ['r', 'wss://a.example.com'],
      ]);
      final second = relayList([
        ['r', 'wss://b.example.com'],
      ]);
      final lowest = first.id.compareTo(second.id) < 0 ? first : second;
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [
          await startRelay([first, second]),
        ],
      );

      expect((await fetcher.fetch(alice))?.id, lowest.id);
    });

    test('also asks the home relays of the pubkey', () async {
      final current = relayList([
        ['r', 'wss://home.example.com'],
      ]);
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [],
        homeRelayList: HomeRelayList([
          await startRelay([current]),
        ]),
      );

      expect((await fetcher.fetch(alice))?.id, current.id);
    });

    test('ignores events that do not match the filter', () async {
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [
          await startRelay([
            relayList([
              ['r', 'wss://bob.example.com'],
            ], pubKey: bob),
            relayList([
              ['r', 'wss://note.example.com'],
            ], kind: 1),
          ]),
        ],
      );

      expect(await fetcher.fetch(alice), isNull);
    });

    test('gives up on a relay that never answers', () async {
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [await startSilentRelay()],
        timeout: const Duration(milliseconds: 200),
      );

      expect(await fetcher.fetch(alice), isNull);
    });

    test('watches each newer list, ending on the newest', () async {
      final newest = relayList([], createdAt: 3000);
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [
          await startRelay([
            relayList([], createdAt: 2000),
            relayList([], createdAt: 1000),
            newest,
          ]),
        ],
      );

      final versions = await fetcher.watch(alice).toList();

      expect(versions.last.id, newest.id);
      for (var i = 1; i < versions.length; i++) {
        expect(versions[i].createdAt, greaterThan(versions[i - 1].createdAt));
      }
    });

    test('watches a list before a relay that never answers', () async {
      final current = relayList([]);
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [
          await startRelay([current]),
          await startSilentRelay(),
        ],
        timeout: const Duration(minutes: 1),
      );

      expect((await fetcher.watch(alice).first).id, current.id);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('looks up a pubkey watched twice at the same time once', () async {
      final current = relayList([]);
      final relay = LocalRelay([current]);
      await relay.start();
      relays.add(relay);
      final fetcher = Nip65Fetcher(reqs: reqs, relays: [relay.url]);

      final lists = await Future.wait([
        fetcher.fetch(alice),
        fetcher.fetch(alice),
      ]);

      expect([for (final list in lists) list?.id], [current.id, current.id]);
      expect(relay.reqCount, 1);
    });

    test('reuses a lookup that finished less than maxAge ago', () async {
      final current = relayList([]);
      final relay = LocalRelay([current]);
      await relay.start();
      relays.add(relay);
      final fetcher = Nip65Fetcher(reqs: reqs, relays: [relay.url]);

      await fetcher.fetch(alice);

      expect((await fetcher.fetch(alice))?.id, current.id);
      expect(relay.reqCount, 1);
    });

    test('looks up again once maxAge passed', () async {
      final relay = LocalRelay([relayList([])]);
      await relay.start();
      relays.add(relay);
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [relay.url],
        maxAge: Duration.zero,
      );

      await fetcher.fetch(alice);
      await fetcher.fetch(alice);

      expect(relay.reqCount, 2);
    });

    test('keeps looking up after its last watcher left', () async {
      final current = relayList([]);
      final relay = LocalRelay([current]);
      await relay.start();
      relays.add(relay);
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: [relay.url, await startSilentRelay()],
        timeout: const Duration(milliseconds: 500),
      );

      await fetcher.watch(alice).first;

      expect((await fetcher.fetch(alice))?.id, current.id);
      expect(relay.reqCount, 1);
    });
  });

  group('Nip65Fetcher lookup', () {
    test('tells a missing list from an unanswered lookup', () async {
      Future<EventLookup> lookupOn(List<String> urls) => Nip65Fetcher(
        reqs: reqs,
        relays: urls,
        timeout: const Duration(milliseconds: 200),
      ).lookup(alice);
      final current = relayList([]);
      final silent = await startSilentRelay();

      final found = await lookupOn([
        await startRelay([current]),
      ]);
      final missing = await lookupOn([await startRelay([])]);
      final unanswered = await lookupOn([silent]);
      final unasked = await lookupOn([]);

      expect((found as EventFound).event.id, current.id);
      expect(missing, isA<EventNotFound>());
      expect((unanswered as EventUnavailable).reason, contains(silent));
      expect((unasked as EventUnavailable).reason, 'no relay asked');
    });

    group('with a cache and checks', () {
      late MemoryCache cache;
      late MemoryUrlListCheckStore checks;

      setUp(() {
        cache = MemoryCache();
        checks = MemoryUrlListCheckStore();
      });

      /// A new fetcher each time, as after a restart.
      Nip65Fetcher fetcherOn(List<String> urls) => Nip65Fetcher(
        reqs: reqs,
        relays: urls,
        cache: cache,
        checks: checks,
        timeout: const Duration(milliseconds: 200),
      );

      Future<void> checked({required bool found, required Duration ago}) =>
          checks.write(
            UrlListCheck(
              pubkey: alice,
              kind: 10002,
              checkedAt: DateTime.now().toUtc().subtract(ago),
              found: found,
            ),
          );

      test('starts on the cached list and caches newer ones', () async {
        final old = relayList([], createdAt: 1000);
        final current = relayList([], createdAt: 2000);
        await cache.save(old);

        final versions = await fetcherOn([
          await startRelay([current]),
        ]).watch(alice).toList();

        expect(
          [for (final version in versions) version.id],
          [old.id, current.id],
        );
        expect((await cache.load(kind: 10002, pubKey: alice))?.id, current.id);
      });

      test('reads a freshly checked list from the cache', () async {
        final relay = await startCountedRelay([relayList([])]);

        await fetcherOn([relay.url]).fetch(alice);

        expect(await fetcherOn([relay.url]).fetch(alice), isNotNull);
        expect(relay.reqCount, 1);
        expect((await checks.read(alice, 10002))?.found, isTrue);
      });

      test('a freshly checked missing list needs no relay', () async {
        final relay = await startCountedRelay([]);

        await fetcherOn([relay.url]).lookup(alice);

        expect(
          await fetcherOn([relay.url]).lookup(alice),
          isA<EventNotFound>(),
        );
        expect(relay.reqCount, 1);
      });

      test('asks the relays again once the check is stale', () async {
        final current = relayList([], createdAt: 2000);
        await cache.save(relayList([], createdAt: 1000));
        await checked(found: true, ago: const Duration(hours: 1));
        final relay = await startCountedRelay([current]);

        expect((await fetcherOn([relay.url]).fetch(alice))?.id, current.id);
        expect(relay.reqCount, 1);
      });

      test('a stale list holds while no relay answers', () async {
        final cached = relayList([]);
        await cache.save(cached);
        await checked(found: true, ago: const Duration(hours: 1));

        final lookup = await fetcherOn([
          await startSilentRelay(),
        ]).lookup(alice);

        expect((lookup as EventFound).event.id, cached.id);
      });

      test(
        'a stale missing list stays missing while no relay answers',
        () async {
          await checked(found: false, ago: const Duration(hours: 1));

          expect(
            await fetcherOn([await startSilentRelay()]).lookup(alice),
            isA<EventNotFound>(),
          );
        },
      );

      test(
        'a list never checked is unavailable while no relay answers',
        () async {
          expect(
            await fetcherOn([await startSilentRelay()]).lookup(alice),
            isA<EventUnavailable>(),
          );
          expect(await checks.read(alice, 10002), isNull);
        },
      );

      test('asks again for a list found but gone from the cache', () async {
        await checked(found: true, ago: Duration.zero);
        final relay = await startCountedRelay([relayList([])]);

        expect(await fetcherOn([relay.url]).fetch(alice), isNotNull);
        expect(relay.reqCount, 1);
      });

      test('sees a list cached since the check said there was none', () async {
        await checked(found: false, ago: Duration.zero);
        final cached = relayList([]);
        await cache.save(cached);
        final relay = await startCountedRelay([]);

        expect((await fetcherOn([relay.url]).fetch(alice))?.id, cached.id);
        expect(relay.reqCount, 0);
      });

      test('distrusts a check from the future', () async {
        await checked(found: false, ago: const Duration(hours: -1));
        final relay = await startCountedRelay([relayList([])]);

        expect(await fetcherOn([relay.url]).fetch(alice), isNotNull);
        expect(relay.reqCount, 1);
      });

      test('sees a list saved to the cache since the last lookup', () async {
        final relay = await startCountedRelay([relayList([], createdAt: 1000)]);
        final fetcher = fetcherOn([relay.url]);
        await fetcher.fetch(alice);

        final current = relayList([], createdAt: 2000);
        await cache.save(current);

        expect((await fetcher.fetch(alice))?.id, current.id);
        expect(relay.reqCount, 1);
      });
    });
  });

  group('MetadataFetcher', () {
    test('keeps the newest metadata across relays', () async {
      final old = metadata('old', createdAt: 1000);
      final current = metadata('new', createdAt: 2000);
      final fetcher = MetadataFetcher(
        reqs: reqs,
        relays: [
          await startRelay([old]),
          await startRelay([current]),
        ],
      );

      expect((await fetcher.fetch(alice))?.id, current.id);
    });

    Future<Nip65Fetcher> nip65Listing(List<List<String>> tags) async =>
        Nip65Fetcher(
          reqs: reqs,
          relays: [
            await startRelay([relayList(tags)]),
          ],
        );

    test('asks the write relays of the pubkey, not its read relays', () async {
      final onWrite = metadata('write', createdAt: 1000);
      final onRead = metadata('read', createdAt: 2000);
      final writeRelay = await startRelay([onWrite]);
      final readRelay = await startRelay([onRead]);
      final fetcher = MetadataFetcher(
        reqs: reqs,
        relays: [],
        nip65Fetcher: await nip65Listing([
          ['r', writeRelay, 'write'],
          ['r', readRelay, 'read'],
        ]),
      );

      expect((await fetcher.fetch(alice))?.id, onWrite.id);
    });

    test(
      'keeps newer metadata from the write relays than the indexers',
      () async {
        final onIndexer = metadata('old', createdAt: 1000);
        final onWrite = metadata('new', createdAt: 2000);
        final writeRelay = await startRelay([onWrite]);
        final fetcher = MetadataFetcher(
          reqs: reqs,
          relays: [
            await startRelay([onIndexer]),
          ],
          nip65Fetcher: await nip65Listing([
            ['r', writeRelay],
          ]),
        );

        expect((await fetcher.fetch(alice))?.id, onWrite.id);
      },
    );

    test('finds nothing for a pubkey without write relays', () async {
      final readRelay = await startRelay([metadata('read')]);
      final fetcher = MetadataFetcher(
        reqs: reqs,
        relays: [],
        nip65Fetcher: await nip65Listing([
          ['r', readRelay, 'read'],
        ]),
      );

      expect(await fetcher.fetch(alice), isNull);
    });

    test('asks the write relays as soon as a relay list arrives', () async {
      final current = metadata('alice');
      final writeRelay = await startRelay([current]);
      final fetcher = MetadataFetcher(
        reqs: reqs,
        relays: [],
        nip65Fetcher: Nip65Fetcher(
          reqs: reqs,
          relays: [
            await startRelay([
              relayList([
                ['r', writeRelay],
              ]),
            ]),
            await startSilentRelay(),
          ],
          timeout: const Duration(minutes: 1),
        ),
      );

      expect((await fetcher.watch(alice).first).id, current.id);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('asks a write relay that is also an indexer once', () async {
      final relay = LocalRelay([metadata('alice')]);
      await relay.start();
      relays.add(relay);
      final fetcher = MetadataFetcher(
        reqs: reqs,
        relays: [relay.url],
        nip65Fetcher: await nip65Listing([
          ['r', relay.url],
        ]),
      );

      await fetcher.fetch(alice);

      expect(relay.reqCount, 1);
    });

    test('ignores events that do not match the filter', () async {
      final fetcher = MetadataFetcher(
        reqs: reqs,
        relays: [
          await startRelay([
            metadata('bob', pubKey: bob),
            relayList([
              ['r', 'wss://a.example.com'],
            ]),
          ]),
        ],
      );

      expect(await fetcher.fetch(alice), isNull);
    });
  });

  group('OutboxFetcher lookups', () {
    test('looks up a pubkey watched and looked up at once once', () async {
      final current = metadata('alice');
      final relay = await startCountedRelay([current]);
      final fetcher = MetadataFetcher(reqs: reqs, relays: [relay.url]);

      final (profile, lookup) = await (
        fetcher.fetch(alice),
        fetcher.lookup(alice),
      ).wait;

      expect(profile?.id, current.id);
      expect((lookup as EventFound).event.id, current.id);
      expect(relay.reqCount, 1);
    });

    test('reuses a lookup that finished less than maxAge ago', () async {
      final current = metadata('alice');
      final relay = await startCountedRelay([current]);
      final fetcher = MetadataFetcher(reqs: reqs, relays: [relay.url]);

      await fetcher.fetch(alice);

      expect((await fetcher.fetch(alice))?.id, current.id);
      expect(relay.reqCount, 1);
    });

    test('looks up again once maxAge passed', () async {
      final relay = await startCountedRelay([metadata('alice')]);
      final fetcher = MetadataFetcher(
        reqs: reqs,
        relays: [relay.url],
        maxAge: Duration.zero,
      );

      await fetcher.fetch(alice);
      await fetcher.fetch(alice);

      expect(relay.reqCount, 2);
    });

    test('keeps a check for each d tag of a kind', () async {
      final checks = MemoryUrlListCheckStore();
      final relay = await startRelay([
        relayList([
          ['d', 'b'],
        ], kind: 30000),
      ]);
      OutboxFetcher fetcherOf(String dTag) => OutboxFetcher(
        reqs: reqs,
        kind: 30000,
        dTag: dTag,
        relays: [relay],
        checks: checks,
      );

      expect(await fetcherOf('a').lookup(alice), isA<EventNotFound>());
      expect(await fetcherOf('b').lookup(alice), isA<EventFound>());
      expect((await checks.read(alice, 30000, dTag: 'a'))?.found, isFalse);
      expect((await checks.read(alice, 30000, dTag: 'b'))?.found, isTrue);
    });
  });

  test('dmRelaysOf keeps the relay tags, each once, in order', () {
    final list = relayList([
      ['relay', 'wss://b.example.com/'],
      ['r', 'wss://r.example.com'],
      ['relay', 'wss://a.example.com'],
      ['relay', 'wss://B.example.com'],
    ], kind: 10050);

    expect(dmRelaysOf(list), ['wss://b.example.com', 'wss://a.example.com']);
  });

  group('DmRelaysFetcher', () {
    Nip01Event dmRelayList(String relay, {int createdAt = 1000}) => relayList(
      [
        ['relay', relay],
      ],
      kind: 10050,
      createdAt: createdAt,
    );

    test('keeps the newest list across write relays and indexers', () async {
      final onIndexer = dmRelayList('wss://old.example.com', createdAt: 1000);
      final onWrite = dmRelayList('wss://new.example.com', createdAt: 2000);
      final writeRelay = await startRelay([onWrite]);
      final fetcher = DmRelaysFetcher(
        reqs: reqs,
        relays: [
          await startRelay([onIndexer]),
        ],
        nip65Fetcher: Nip65Fetcher(
          reqs: reqs,
          relays: [
            await startRelay([
              relayList([
                ['r', writeRelay],
              ]),
            ]),
          ],
        ),
      );

      final list = await fetcher.fetch(alice);

      expect(list?.id, onWrite.id);
      expect(dmRelaysOf(list!), ['wss://new.example.com']);
    });

    test('ignores events that do not match the filter', () async {
      final fetcher = DmRelaysFetcher(
        reqs: reqs,
        relays: [
          await startRelay([
            relayList(
              [
                ['relay', 'wss://bob.example.com'],
              ],
              kind: 10050,
              pubKey: bob,
            ),
            metadata('alice'),
            relayList([
              ['relay', 'wss://a.example.com'],
            ]),
          ]),
        ],
      );

      expect(await fetcher.fetch(alice), isNull);
    });

    test('tells a missing list from an unanswered lookup', () async {
      const timeout = Duration(milliseconds: 200);
      Future<EventLookup> lookupOn(String url) => DmRelaysFetcher(
        reqs: reqs,
        relays: [url],
        nip65Fetcher: Nip65Fetcher(reqs: reqs, relays: [url], timeout: timeout),
        timeout: timeout,
      ).lookup(alice);

      expect(await lookupOn(await startRelay([])), isA<EventNotFound>());
      expect(await lookupOn(await startSilentRelay()), isA<EventUnavailable>());
    });

    test('is unavailable while no relay answers for the relay list', () async {
      const timeout = Duration(milliseconds: 200);
      final checks = MemoryUrlListCheckStore();

      final lookup = await DmRelaysFetcher(
        reqs: reqs,
        relays: [await startRelay([])],
        nip65Fetcher: Nip65Fetcher(
          reqs: reqs,
          relays: [await startSilentRelay()],
          timeout: timeout,
        ),
        checks: checks,
        timeout: timeout,
      ).lookup(alice);

      expect((lookup as EventUnavailable).reason, contains('relay list'));
      expect(await checks.read(alice, 10050), isNull);
    });

    test('reads a freshly checked list from the cache', () async {
      final cache = MemoryCache();
      final checks = MemoryUrlListCheckStore();
      final relay = await startCountedRelay([
        dmRelayList('wss://dm.example.com'),
      ]);
      DmRelaysFetcher fetcher() => DmRelaysFetcher(
        reqs: reqs,
        relays: [relay.url],
        cache: cache,
        checks: checks,
      );

      await fetcher().fetch(alice);
      final list = await fetcher().fetch(alice);

      expect(dmRelaysOf(list!), ['wss://dm.example.com']);
      expect(relay.reqCount, 1);
    });
  });

  test(
    'blossomServersOf keeps the http(s) server tags, each once, in order',
    () {
      final list = relayList([
        ['server', 'https://B.example.com/'],
        ['r', 'https://r.example.com'],
        ['server', 'wss://relay.example.com'],
        ['server', 'not a url'],
        ['server', 'http://a.example.com:80/media/'],
        ['server', ' https://b.example.com '],
      ], kind: 10063);

      expect(blossomServersOf(list), [
        'https://b.example.com',
        'http://a.example.com/media',
      ]);
    },
  );

  group('BlossomServersFetcher', () {
    Nip01Event serverList(String server, {int createdAt = 1000}) => relayList(
      [
        ['server', server],
      ],
      kind: 10063,
      createdAt: createdAt,
    );

    test('keeps the newest list across write relays and indexers', () async {
      final onIndexer = serverList('https://old.example.com', createdAt: 1000);
      final onWrite = serverList('https://new.example.com', createdAt: 2000);
      final writeRelay = await startRelay([onWrite]);
      final fetcher = BlossomServersFetcher(
        reqs: reqs,
        relays: [
          await startRelay([onIndexer]),
        ],
        nip65Fetcher: Nip65Fetcher(
          reqs: reqs,
          relays: [
            await startRelay([
              relayList([
                ['r', writeRelay],
              ]),
            ]),
          ],
        ),
      );

      final list = await fetcher.fetch(alice);

      expect(list?.id, onWrite.id);
      expect(blossomServersOf(list!), ['https://new.example.com']);
    });

    test('ignores events that do not match the filter', () async {
      final fetcher = BlossomServersFetcher(
        reqs: reqs,
        relays: [
          await startRelay([
            relayList(
              [
                ['server', 'https://bob.example.com'],
              ],
              kind: 10063,
              pubKey: bob,
            ),
            relayList([
              ['server', 'https://a.example.com'],
            ], kind: 10050),
          ]),
        ],
      );

      expect(await fetcher.fetch(alice), isNull);
    });
  });

  group('HomeRelayListFetcher', () {
    Nip01Event homeRelayList(String relay, {int createdAt = 1000}) => relayList(
      [
        ['d', 'home-relays'],
        ['relay', relay],
      ],
      kind: 36205,
      createdAt: createdAt,
    );

    test('keeps the newest list across write relays and indexers', () async {
      final onIndexer = homeRelayList('wss://old.example.com', createdAt: 1000);
      final onWrite = homeRelayList('wss://new.example.com', createdAt: 2000);
      final writeRelay = await startRelay([onWrite]);
      final fetcher = HomeRelayListFetcher(
        reqs: reqs,
        relays: [
          await startRelay([onIndexer]),
        ],
        nip65Fetcher: Nip65Fetcher(
          reqs: reqs,
          relays: [
            await startRelay([
              relayList([
                ['r', writeRelay],
              ]),
            ]),
          ],
        ),
      );

      final list = await fetcher.fetch(alice);

      expect(list?.id, onWrite.id);
      expect(HomeRelayList.fromEvent(list!).candidates, [
        'wss://new.example.com',
      ]);
    });

    test('ignores events that do not match the filter', () async {
      final fetcher = HomeRelayListFetcher(
        reqs: reqs,
        relays: [
          await startRelay([
            relayList(
              [
                ['d', 'home-relays'],
                ['relay', 'wss://bob.example.com'],
              ],
              kind: 36205,
              pubKey: bob,
            ),
            relayList([
              ['d', 'other'],
              ['relay', 'wss://other.example.com'],
            ], kind: 36205),
            relayList([
              ['relay', 'wss://a.example.com'],
            ], kind: 10050),
          ]),
        ],
      );

      expect(await fetcher.fetch(alice), isNull);
    });
  });

  group('fetcherUrlListFn', () {
    UrlListFn listsOn(
      String url, {
      Duration timeout = const Duration(seconds: 5),
    }) {
      final nip65 = Nip65Fetcher(reqs: reqs, relays: [url], timeout: timeout);
      return fetcherUrlListFn(
        nip65: nip65,
        dmRelays: DmRelaysFetcher(
          reqs: reqs,
          relays: [url],
          nip65Fetcher: nip65,
          timeout: timeout,
        ),
        blossomServers: BlossomServersFetcher(
          reqs: reqs,
          relays: [url],
          nip65Fetcher: nip65,
          timeout: timeout,
        ),
      );
    }

    test('reads each list kind', () async {
      // the write relays of alice do not exist, bob has none to ask
      final lists = listsOn(
        await startRelay([
          relayList([
            ['r', 'wss://both.example.com'],
            ['r', 'wss://read.example.com', 'read'],
            ['r', 'wss://write.example.com', 'write'],
          ]),
          relayList(
            [
              ['relay', 'wss://dm.example.com'],
            ],
            kind: 10050,
            pubKey: bob,
          ),
          relayList(
            [
              ['server', 'https://cdn.example.com'],
            ],
            kind: 10063,
            pubKey: bob,
          ),
        ]),
      );
      Future<List<String>> urlsOf(String pubKey, UrlListKind kind) async =>
          (await lists(pubKey, kind, const []) as UrlListFound).urls;

      expect(await urlsOf(alice, UrlListKind.outbox), [
        'wss://both.example.com',
        'wss://write.example.com',
      ]);
      expect(await urlsOf(alice, UrlListKind.inbox), [
        'wss://both.example.com',
        'wss://read.example.com',
      ]);
      expect(await urlsOf(alice, UrlListKind.nip65), [
        'wss://both.example.com',
        'wss://read.example.com',
        'wss://write.example.com',
      ]);
      expect(await urlsOf(bob, UrlListKind.dm), ['wss://dm.example.com']);
      expect(await urlsOf(bob, UrlListKind.blossom), [
        'https://cdn.example.com',
      ]);
    });

    test('falls back past a missing list, not an unanswered one', () async {
      const set = UrlSet.fallback([
        UrlSet.dm(bob),
        UrlSet.explicit(['wss://default.example.com']),
      ]);

      final answered = await resolveUrlSet(set, listsOn(await startRelay([])));
      final unanswered = await resolveUrlSet(
        set,
        listsOn(
          await startSilentRelay(),
          timeout: const Duration(milliseconds: 200),
        ),
      );

      expect((answered as UrlsResolved).urls, ['wss://default.example.com']);
      expect(unanswered, isA<UrlsUnavailable>());
    });

    test('rejects private relay lists', () async {
      final lists = listsOn(await startRelay([]));

      expect(
        lists(alice, UrlListKind.private, const []),
        throwsUnsupportedError,
      );
    });

    test('requires the fetchers to find write relays with nip65', () {
      final nip65 = Nip65Fetcher(reqs: reqs);

      expect(
        () => fetcherUrlListFn(
          nip65: nip65,
          dmRelays: DmRelaysFetcher(reqs: reqs),
          blossomServers: BlossomServersFetcher(
            reqs: reqs,
            nip65Fetcher: nip65,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
