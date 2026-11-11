import 'dart:async';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_core/src/relay_manager_parts.dart';
import 'package:ndk_core/src/request_state.dart';
import 'package:test/test.dart';

class _Transport implements NostrTransport {
  final String url;
  bool open = true;
  bool closed = false;
  int closes = 0;
  Completer<void>? closeGate;
  final controller = StreamController<dynamic>.broadcast();
  final sent = <dynamic>[];
  _Transport(this.url);
  @override
  Future<void> ready = Future.value();
  @override
  bool isOpen() => open && !closed;
  @override
  bool isConnecting() => false;
  @override
  Future<void> close() async {
    closes++;
    closed = true;
    await closeGate?.future;
  }

  /// The socket ends on the relay side.
  void drop() {
    open = false;
    controller.close();
  }

  @override
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    Function()? onDone,
  }) => controller.stream.listen(onData, onError: onError, onDone: onDone);
  @override
  void send(dynamic data) => sent.add(data);
  @override
  int? closeCode() => null;
  @override
  String? closeReason() => null;
}

class _Factory implements NostrTransportFactory {
  final created = <_Transport>[];
  bool openNext = true;
  Completer<void>? readyGate;

  /// handed out again instead of a new transport, the way a factory that
  /// keeps its sockets does
  _Transport? reuse;
  int calls = 0;
  @override
  NostrTransport call(String url) {
    calls++;
    // bounded, so a retry loop fails the test instead of starving it
    final reused = reuse;
    if (reused != null && calls < 20) return reused;
    expect(
      created.where((t) => t.url == url).every((t) => t.closed),
      isTrue,
      reason: 'retire the old transport before its replacement',
    );
    final transport = _Transport(url)..open = openNext;
    if (readyGate != null) transport.ready = readyGate!.future;
    created.add(transport);
    return transport;
  }
}

void main() {
  const url = 'wss://relay.example';
  final key = RelayConnectionKey.anonymous(url);
  late RelayManagerParts parts;
  late _Factory factory;
  late RelayManager manager;
  late RequestState subscription;
  Future<bool> connect([String relayUrl = url]) async =>
      (await manager.connectRelay(
        dirtyUrl: relayUrl,
        connectTimeout: const Duration(seconds: 1),
      )).connected;
  int replays(_Transport transport) => transport.sent
      .where((data) => (data as String).startsWith('["REQ","live"'))
      .length;
  int allReplays() => factory.created.map(replays).fold(0, (a, b) => a + b);
  RelayRequestStatus status() => subscription.relayOutcomes[url]!.status;
  setUp(() {
    factory = _Factory();
    manager = RelayManager(nostrTransportFactory: factory);
    parts = relayManagerParts(manager);
    subscription = RequestState.subscription('live')
      ..addRequest(key, [
        Filter(kinds: [1]),
      ]);
    subscription.networkController.stream.listen((_) {});
    parts.requests.inFlight[subscription.id] = subscription;
  });
  tearDown(() async {
    await subscription.close();
    await manager.closeAllTransports();
    for (final transport in factory.created) {
      await transport.close();
      if (!transport.controller.isClosed) await transport.controller.close();
    }
  });

  test('replacement retires the old transport', () async {
    expect(await connect(), isTrue);
    final old = factory.created.single..open = false;
    expect(await connect(), isTrue);
    expect(old.closed, isTrue);
    expect(factory.created.where((t) => t.isOpen()).length, 1);
    expect(parts.connections.relays.length, 1);
    await manager.closeAllTransports();
    expect(factory.created.where((t) => t.isOpen()), isEmpty);
    expect(parts.connections.relays, isEmpty);
  });

  test(
    'concurrent replacement waits for one old close and creates one transport',
    () async {
      await connect();
      final old = factory.created.single..open = false;
      old.closeGate = Completer<void>();
      final first = connect();
      final second = connect();
      await pumpEventQueue();
      expect(factory.created.length, 1);
      expect(old.closes, 1);
      old.closeGate!.complete();
      expect(await Future.wait([first, second]), [true, true]);
      expect(factory.created.length, 2);
    },
  );

  test(
    'removal during retirement never creates an untracked replacement',
    () async {
      await connect();
      final old = factory.created.single..open = false;
      old.closeGate = Completer<void>();
      final replacing = connect();
      await pumpEventQueue();
      await manager.closeConnection(key);
      old.closeGate!.complete();
      expect(await replacing, isFalse);
      expect(factory.created.length, 1);
      expect(parts.connections.relays, isEmpty);
    },
  );

  test(
    'a retired transport ending late leaves the current one alone',
    () async {
      await connect();
      final old = factory.created.single..open = false;
      await connect();
      final current = parts.connections.relays[key]!;
      current.stats.openRequestIds.add('live-request');
      final errors = current.stats.connectionErrors;
      old.controller.addError(StateError('late error'));
      old.drop();
      await pumpEventQueue();
      expect(current.stats.openRequestIds, {'live-request'});
      expect(current.stats.connectionErrors, errors);
      expect(factory.created, hasLength(2));
      expect(allReplays(), 0);
    },
  );

  test(
    'close during pending handshake prevents late connect success',
    () async {
      factory.openNext = false;
      factory.readyGate = Completer<void>();
      final connecting = connect();
      await pumpEventQueue();
      final transport = factory.created.single;
      await manager.closeAllTransports();
      transport.open = true;
      factory.readyGate!.complete();
      expect(await connecting.timeout(const Duration(seconds: 2)), isFalse);
      expect(parts.connections.relays, isEmpty);
      expect(transport.closed, isTrue);
      await pumpEventQueue();
      expect(allReplays(), 0);
    },
  );

  test('a dropped socket is replaced and its subscriptions replayed', () async {
    await connect();

    factory.created.single.drop();
    await pumpEventQueue();

    expect(factory.created, hasLength(2));
    expect(factory.created.first.closed, isTrue);
    expect(replays(factory.created.last), 1);
    expect(manager.isConnectionOpen(key), isTrue);
    expect(parts.connections.relays[key]!.stats.connectionErrors, 1);
  });

  test('a socket ending with an error is replaced too', () async {
    await connect();

    factory.created.single.controller.addError(StateError('socket blew up'));
    await pumpEventQueue();

    expect(factory.created, hasLength(2));
    expect(replays(factory.created.last), 1);
  });

  test(
    'a dropped socket that cannot reconnect yet is retried after a wait',
    () async {
      await connect();
      factory.openNext = false;

      factory.created.single.drop();
      await pumpEventQueue();

      expect(factory.created, hasLength(2));
      expect(manager.isConnectionOpen(key), isFalse);
      expect(status(), RelayRequestStatus.pending);

      factory.openNext = true;
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(factory.created, hasLength(3));
      expect(manager.isConnectionOpen(key), isTrue);
      expect(replays(factory.created.last), 1);
    },
  );

  test('a refused connect is tried again until connectTimeout', () async {
    factory.openNext = false;
    final connecting = connect();
    await pumpEventQueue();
    expect(factory.created, hasLength(1));

    factory.openNext = true;

    expect(await connecting, isTrue);
    expect(factory.created, hasLength(2));
    expect(factory.created.first.closed, isTrue);
  });

  test('a refused connect gives up once connectTimeout ran out', () async {
    factory.openNext = false;
    final elapsed = Stopwatch()..start();

    expect(await connect(), isFalse);

    expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 1500)));
    expect(factory.created.where((t) => !t.closed), isEmpty);
  });

  test('a socket ending while it opens waits for the backoff', () async {
    await connect();
    final dead = factory.created.single;
    factory.reuse = dead;

    dead.drop();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(factory.calls, 2, reason: 'retried without waiting');
  });

  test('a socket opened by someone else ends the wait at once', () async {
    await connect();
    factory.openNext = false;
    factory.created.single.drop();
    await pumpEventQueue();
    factory.openNext = true;

    expect(await connect(), isTrue);
    await pumpEventQueue();

    expect(factory.created, hasLength(3));
    expect(replays(factory.created.last), 1);
  });

  test('closing a connection stops bringing it back', () async {
    await connect();
    factory.openNext = false;
    factory.created.single.drop();
    await pumpEventQueue();

    await manager.closeConnection(key);
    factory.openNext = true;
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(factory.created, hasLength(2));
    expect(parts.connections.relays, isEmpty);
  });

  test(
    'without reconnects, a dropped socket ends its requests as disconnected',
    () async {
      manager.allowReconnectRelays = false;
      await connect();

      factory.created.single.drop();
      await pumpEventQueue();

      expect(factory.created, hasLength(1));
      expect(status(), RelayRequestStatus.disconnected);
    },
  );

  test(
    'reconnectClosedConnections replaces a dead transport and replays',
    () async {
      await connect();
      factory.created.single.open = false;

      await manager.reconnectClosedConnections();
      await pumpEventQueue();

      expect(factory.created, hasLength(2));
      expect(factory.created.first.closed, isTrue);
      expect(replays(factory.created.last), 1);
      expect(manager.isConnectionOpen(key), isTrue);
    },
  );

  test('reconnectClosedConnections reconnects every relay at once', () async {
    const other = 'wss://other.example';
    await connect();
    await connect(other);
    for (final transport in factory.created) {
      transport.open = false;
    }
    factory.openNext = false;
    factory.readyGate = Completer<void>();

    final reconnecting = manager.reconnectClosedConnections();
    await pumpEventQueue();

    final replacements = factory.created.skip(2).toList();
    expect(replacements.map((t) => t.url), unorderedEquals([url, other]));
    for (final transport in replacements) {
      transport.open = true;
    }
    factory.readyGate!.complete();
    await reconnecting;

    expect(manager.isConnectionOpen(key), isTrue);
    expect(manager.isRelayConnected(other), isTrue);
  });

  test('a replay skips the requests the socket already carries', () async {
    await connect();
    final connectivity = parts.connections.relays[key]!;
    manager.send(key, [
      'REQ',
      'live',
      {
        'kinds': [1],
      },
    ]);
    await pumpEventQueue();

    parts.requests.replayOn(connectivity);
    await pumpEventQueue();

    expect(replays(factory.created.single), 1);
  });
}
