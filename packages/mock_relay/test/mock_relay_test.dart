import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:test/test.dart';

const alice =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const bob = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Nip01Event note({
  String pubKey = alice,
  int kind = Nip01Event.kTextNoteKind,
  List<List<String>> tags = const [],
  String content = 'note',
  int createdAt = 1000,
}) => Nip01Event(
  pubKey: pubKey,
  kind: kind,
  tags: tags,
  content: content,
  createdAt: createdAt,
);

Future<MockRelay> startRelay({Iterable<Nip01Event> events = const []}) async {
  final relay = MockRelay();
  await relay.start(events: events);
  addTearDown(relay.stop);
  return relay;
}

/// A bare websocket client, so these tests do not depend on dostr_core.
class Client {
  Client._(this._socket) {
    _socket.listen((data) {
      final message = jsonDecode(data as String) as List<dynamic>;
      messages.add(message);
      _incoming.add(message);
    }, onDone: _incoming.close);
  }

  static Future<Client> connect(MockRelay relay) async {
    final client = Client._(await WebSocket.connect(relay.url));
    addTearDown(client._socket.close);
    return client;
  }

  final WebSocket _socket;
  final List<List<dynamic>> messages = [];
  final _incoming = StreamController<List<dynamic>>.broadcast();
  var _nextId = 0;

  bool get closed => _socket.readyState == WebSocket.closed;

  void send(List<dynamic> message) => _socket.add(jsonEncode(message));

  Future<List<dynamic>> waitFor(bool Function(List<dynamic> message) test) {
    final found = messages.where(test).firstOrNull;
    if (found != null) return Future.value(found);
    return _incoming.stream.firstWhere(test).timeout(Duration(seconds: 2));
  }

  /// the events of [subscriptionId] received so far
  List<Nip01Event> eventsOf(String subscriptionId) => [
    for (final message in messages)
      if (message[0] == 'EVENT' && message[1] == subscriptionId)
        Nip01Event.fromJson(message[2]),
  ];

  Future<List<dynamic>> publish(Nip01Event event) {
    send(['EVENT', event.toJson()]);
    return waitFor((m) => m[0] == 'OK' && m[1] == event.id);
  }

  /// Opens a subscription and waits for its EOSE.
  Future<String> subscribe(Filter filter) async {
    final id = 'sub${_nextId++}';
    send(['REQ', id, filter.toMap()]);
    await waitFor((m) => m[0] == 'EOSE' && m[1] == id);
    return id;
  }

  Future<List<Nip01Event>> query(Filter filter) async =>
      eventsOf(await subscribe(filter));

  /// Everything the relay sent this socket before now has arrived.
  Future<void> roundTrip() => subscribe(Filter(ids: []));
}

void main() {
  group('stored events', () {
    test('a REQ gets the stored events it matches, then EOSE', () async {
      final mine = note(content: 'mine');
      final relay = await startRelay(
        events: [
          mine,
          note(pubKey: bob),
        ],
      );
      final client = await Client.connect(relay);

      final received = await client.query(Filter(authors: [alice]));

      expect(received.map((e) => e.id), [mine.id]);
    });

    test('a tag filter only matches the events carrying the tag', () async {
      final tagged = note(
        tags: [
          ['r', 'a'],
        ],
      );
      final otherValue = note(
        tags: [
          ['r', 'b'],
        ],
      );
      final valueless = note(
        tags: [
          ['r'],
        ],
      );
      final relay = await startRelay(events: [tagged, otherValue, valueless]);
      final client = await Client.connect(relay);

      final received = await client.query(
        Filter(
          tags: {
            '#r': ['a'],
          },
        ),
      );

      expect(received.map((e) => e.id), [tagged.id]);
    });

    test('several tag filters must all match', () async {
      final both = note(
        tags: [
          ['p', bob],
          ['t', 'nostr'],
        ],
      );
      final onlyP = note(
        tags: [
          ['p', bob],
        ],
      );
      final relay = await startRelay(events: [both, onlyP]);
      final client = await Client.connect(relay);

      final received = await client.query(
        Filter(
          pTags: [bob],
          tags: {
            '#t': ['nostr'],
          },
        ),
      );

      expect(received.map((e) => e.id), [both.id]);
    });

    test('a newer replaceable event replaces the stored one', () async {
      final relay = await startRelay();
      final client = await Client.connect(relay);
      final older = note(kind: 10002, createdAt: 1000);
      final newer = note(kind: 10002, createdAt: 2000);

      await client.publish(older);
      await client.publish(newer);
      await client.publish(note(kind: 10002, createdAt: 500));

      final received = await client.query(Filter(kinds: [10002]));
      expect(received.map((e) => e.id), [newer.id]);
    });

    test('an addressable event replaces the one with its d tag', () async {
      final relay = await startRelay();
      final client = await Client.connect(relay);
      Nip01Event article(String d, int createdAt) => note(
        kind: 30023,
        tags: [
          ['d', d],
        ],
        createdAt: createdAt,
      );
      final draft = article('post', 1000);
      final finalVersion = article('post', 2000);
      final other = article('other', 1000);

      await client.publish(draft);
      await client.publish(finalVersion);
      await client.publish(other);

      final received = await client.query(Filter(kinds: [30023]));
      expect(
        received.map((e) => e.id),
        unorderedEquals([finalVersion.id, other.id]),
      );
    });

    test('a deletion removes the events of its author only', () async {
      final mine = note(content: 'mine');
      final hers = note(pubKey: bob, content: 'hers');
      final relay = await startRelay(events: [mine, hers]);
      final client = await Client.connect(relay);

      await client.publish(
        note(
          kind: 5,
          tags: [
            ['e', mine.id],
            ['e', hers.id],
          ],
        ),
      );

      final received = await client.query(
        Filter(kinds: [Nip01Event.kTextNoteKind]),
      );
      expect(received.map((e) => e.id), [hers.id]);
    });

    test('the recipient of a gift wrap deletes it', () async {
      final wrap = note(
        pubKey:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        kind: 1059,
        tags: [
          ['p', alice],
        ],
      );
      final relay = await startRelay(events: [wrap]);
      final client = await Client.connect(relay);

      await client.publish(
        note(
          kind: 5,
          tags: [
            ['e', wrap.id],
          ],
        ),
      );

      expect(await client.query(Filter(kinds: [1059])), isEmpty);
    });

    test('a duplicate EVENT is acknowledged and not delivered again', () async {
      final relay = await startRelay();
      final reader = await Client.connect(relay);
      final writer = await Client.connect(relay);
      final id = await reader.subscribe(Filter(authors: [alice]));
      final event = note();

      await writer.publish(event);
      final duplicate = await writer.publish(event);
      await reader.roundTrip();

      expect(duplicate[2], isTrue);
      expect(reader.eventsOf(id), hasLength(1));
    });
  });

  group('live subscriptions', () {
    test('an accepted EVENT reaches the matching subscriptions', () async {
      final relay = await startRelay();
      final reader = await Client.connect(relay);
      final writer = await Client.connect(relay);
      final mine = await reader.subscribe(Filter(authors: [alice]));
      final hers = await reader.subscribe(Filter(authors: [bob]));
      final event = note();

      await writer.publish(event);
      await reader.waitFor((m) => m[0] == 'EVENT' && m[1] == mine);

      expect(reader.eventsOf(mine).map((e) => e.id), [event.id]);
      expect(reader.eventsOf(hers), isEmpty);
    });

    test('an ephemeral event reaches them but is not stored', () async {
      final relay = await startRelay();
      final reader = await Client.connect(relay);
      final writer = await Client.connect(relay);
      final id = await reader.subscribe(Filter(kinds: [21133]));
      final ephemeral = note(kind: 21133);

      await writer.publish(ephemeral);
      await reader.waitFor((m) => m[0] == 'EVENT' && m[1] == id);

      expect(relay.events, isEmpty);
      expect(await writer.query(Filter(kinds: [21133])), isEmpty);
    });

    test(
      'a replaceable event older than the stored one is not delivered',
      () async {
        final relay = await startRelay();
        final reader = await Client.connect(relay);
        final writer = await Client.connect(relay);
        final id = await reader.subscribe(Filter(kinds: [10000]));
        final current = note(kind: 10000, createdAt: 2000);

        await writer.publish(current);
        await reader.waitFor((m) => m[0] == 'EVENT' && m[1] == id);
        await writer.publish(note(kind: 10000, createdAt: 1000));
        await reader.roundTrip();

        expect(reader.eventsOf(id).map((e) => e.id), [current.id]);
      },
    );
  });

  group('maxMessageLength', () {
    final filter = Filter(authors: [alice], search: 'café');
    final req = jsonEncode(['REQ', 'sub0', filter.toMap()]);

    test('a message one UTF-8 byte too long closes the socket', () async {
      final relay = MockRelay(maxMessageLength: utf8.encode(req).length - 1);
      await relay.start(events: [note()]);
      addTearDown(relay.stop);
      final client = await Client.connect(relay);

      client._socket.add(req);
      await client._incoming.stream.drain<void>();

      expect(client._socket.closeCode, WebSocketStatus.messageTooBig);
      expect(relay.oversizedMessages, 1);
      expect(relay.received('REQ'), isEmpty);
    });

    test('a message of exactly that length is answered', () async {
      final relay = MockRelay(maxMessageLength: utf8.encode(req).length);
      await relay.start(events: [note()]);
      addTearDown(relay.stop);
      final client = await Client.connect(relay);

      expect(await client.query(filter), hasLength(1));
      expect(relay.oversizedMessages, 0);
    });

    test('the NIP-11 document publishes it', () {
      final relay = MockRelay(maxSubscriptions: 20, maxMessageLength: 1000);

      expect(relay.relayInfo, {
        'limitation': {'max_subscriptions': 20, 'max_message_length': 1000},
      });
    });
  });

  group('lifecycle', () {
    test('stop closes the client websockets', () async {
      final relay = MockRelay();
      await relay.start();
      final client = await Client.connect(relay);

      await relay.stop();
      await client._incoming.stream.drain<void>();

      expect(client.closed, isTrue);
    });

    test('the url is known before start and kept across restarts', () async {
      final relay = MockRelay();
      final url = relay.url;
      await relay.start();
      await relay.stop();
      await relay.start(events: [note()]);
      addTearDown(relay.stop);

      final client = await Client.connect(relay);

      expect(relay.url, url);
      expect(await client.query(Filter(authors: [alice])), hasLength(1));
    });
  });
}
