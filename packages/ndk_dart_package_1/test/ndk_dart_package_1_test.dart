import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_dart_package_1/ndk_dart_package_1.dart';
import 'package:ndk_nip19/ndk_nip19.dart';
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
          socket.add(
            jsonEncode([
              'EVENT',
              id,
              Nip01EventModel.fromEntity(event).toJson(),
            ]),
          );
        }
        socket.add(jsonEncode(['EOSE', id]));
      });
    });
  }

  Future<void> stop() => _server.close(force: true);
}

/// Serves [body] with [status] on every path, until the test ends.
Future<String> serve(String body, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) {
    request.response
      ..statusCode = status
      ..write(body)
      ..close();
  });
  return 'http://127.0.0.1:${server.port}/list.json';
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

  group('HomeRelayList', () {
    test('computes the home relays of the NIP example', () {
      final list = HomeRelayList([
        'wss://indexer.coracle.social',
        'wss://nostr-pub.wellorder.net',
        'wss://nostr.bitcoiner.social',
        'wss://nostr.data.haus',
        'wss://nostr.oxtr.dev',
        'wss://offchain.pub',
        'wss://purplepag.es',
        'wss://relay.angor.io',
        'wss://relay.coinos.io',
        'wss://relay.ditto.pub',
        'wss://relay.nos.social',
        'wss://relay.nostr.net',
        'wss://relay.nostrplebs.com',
        'wss://relay.primal.net',
        'wss://user.kindpag.es',
        'wss://yabu.me',
      ]);
      final pubKey = Nip19.decode(
        'npub1jlp4rzsraw0nvvuyavgf2z497juw7y44v40ch23lnwzlnre3wuusjhmu65',
      );

      expect(list.homeRelaysOf(pubKey), [
        'wss://relay.angor.io',
        'wss://relay.primal.net',
        'wss://yabu.me',
        'wss://relay.ditto.pub',
        'wss://purplepag.es',
        'wss://relay.coinos.io',
        'wss://nostr.data.haus',
        'wss://indexer.coracle.social',
      ]);
    });

    test('normalizes the candidates and keeps each once', () {
      final list = HomeRelayList([
        'wss://Relay.Example.com/',
        'wss://relay.example.com',
        'https://relay.example.com',
      ]);

      expect(list.candidates, ['wss://relay.example.com']);
    });

    test('reads the relay tags of a home-relays list', () {
      final list = HomeRelayList.fromEvent(
        relayList([
          ['d', 'home-relays'],
          ['relay', 'wss://a.example.com'],
          ['r', 'wss://b.example.com'],
        ], kind: 36205),
      );

      expect(list.candidates, ['wss://a.example.com']);
    });

    test('rejects another list', () {
      final other = relayList([
        ['d', 'other'],
        ['relay', 'wss://a.example.com'],
      ], kind: 36205);

      expect(() => HomeRelayList.fromEvent(other), throwsArgumentError);
    });

    group('fetch', () {
      final verifier = Bip340EventVerifier(useIsolate: false);
      final author = Bip340.generatePrivateKey();
      final other = Bip340.generatePrivateKey();

      Nip01Event listEvent(String pubKey, KeyPair signer) => Bip340.signEvent(
        event: Nip01Event(
          pubKey: pubKey,
          kind: 36205,
          tags: [
            ['d', 'home-relays'],
            ['relay', 'wss://a.example.com'],
          ],
          content: '',
        ),
        privateKey: signer.privateKey!,
      );

      Future<HomeRelayList> fetch(Nip01Event event) async =>
          HomeRelayList.fetch(
            verifier: verifier,
            url: await serve(
              jsonEncode(Nip01EventModel.fromEntity(event).toJson()),
            ),
            author: author.publicKey,
          );

      test('loads the list its author signed', () async {
        final list = await fetch(listEvent(author.publicKey, author));

        expect(list.candidates, ['wss://a.example.com']);
      });

      test('rejects a list of another author', () {
        expect(fetch(listEvent(other.publicKey, other)), throwsFormatException);
      });

      test('rejects a signature from another key', () {
        expect(
          fetch(listEvent(author.publicKey, other)),
          throwsFormatException,
        );
      });

      test('rejects a list changed after it was signed', () {
        final signed = listEvent(author.publicKey, author);
        final changed = Nip01Event(
          id: signed.id,
          sig: signed.sig,
          pubKey: signed.pubKey,
          createdAt: signed.createdAt,
          kind: signed.kind,
          tags: [
            ...signed.tags,
            ['relay', 'wss://b.example.com'],
          ],
          content: signed.content,
        );

        expect(fetch(changed), throwsFormatException);
      });

      test('fails on an HTTP error', () async {
        final url = await serve('', status: 404);

        expect(
          HomeRelayList.fetch(verifier: verifier, url: url),
          throwsA(isA<http.ClientException>()),
        );
      });
    });
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
  });
}
