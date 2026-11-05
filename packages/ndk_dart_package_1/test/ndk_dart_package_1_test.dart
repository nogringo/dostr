import 'dart:convert';
import 'dart:io';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_dart_package_1/ndk_dart_package_1.dart';
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

class AcceptAll implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async => true;
}

/// Answers every REQ with all its [events], whatever the filter, then EOSE.
class LocalRelay {
  final List<Nip01Event> events;
  late final HttpServer _server;

  LocalRelay(this.events);

  String get url => 'ws://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((data) {
        final message = jsonDecode(data as String) as List;
        if (message[0] != 'REQ') return;
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

void main() {
  group('Nip65Fetcher', () {
    late RelayManager relayManager;
    late RelayReqs reqs;
    final relays = <LocalRelay>[];

    Future<String> startRelay(List<Nip01Event> events) async {
      final relay = LocalRelay(events);
      await relay.start();
      relays.add(relay);
      return relay.url;
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
      final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      silent.transform(WebSocketTransformer()).listen((_) {});
      addTearDown(() => silent.close(force: true));
      final fetcher = Nip65Fetcher(
        reqs: reqs,
        relays: ['ws://127.0.0.1:${silent.port}'],
        timeout: const Duration(milliseconds: 200),
      );

      expect(await fetcher.fetch(alice), isNull);
    });
  });
}
