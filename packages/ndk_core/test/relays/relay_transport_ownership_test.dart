import 'dart:async';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_core/src/relay_manager_parts.dart';
import 'package:ndk_core/src/request_state.dart';
import 'package:test/test.dart';

class _Transport implements NostrTransport {
  bool open = true;
  bool closed = false;
  int closes = 0;
  Completer<void>? closeGate;
  final Function? reconnect;
  final Function(int?, Object?, String?)? disconnect;
  final controller = StreamController<dynamic>.broadcast();
  final sent = <dynamic>[];
  _Transport(this.reconnect, this.disconnect);
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

  void recover() {
    if (closed) return;
    open = true;
    reconnect?.call();
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
  @override
  NostrTransport call(
    String url, {
    Function? onReconnect,
    Function(int?, Object?, String?)? onDisconnect,
  }) {
    if (created.isNotEmpty) {
      expect(
        created.last.closed,
        isTrue,
        reason: 'retire old reconnecting transport before replacement',
      );
    }
    final transport = _Transport(onReconnect, onDisconnect)..open = openNext;
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
  Future<bool> connect() async => (await manager.connectRelay(
    dirtyUrl: url,
    connectTimeout: const Duration(seconds: 1),
  )).connected;
  int replays(_Transport transport) => transport.sent
      .where((data) => (data as String).startsWith('["REQ","live"'))
      .length;
  int allReplays() => factory.created.map(replays).fold(0, (a, b) => a + b);
  setUp(() {
    factory = _Factory();
    manager = RelayManager(nostrTransportFactory: factory, bootstrapRelays: []);
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
      await transport.controller.close();
    }
  });

  test(
    'replacement retires old transport so recovery cannot orphan a socket',
    () async {
      expect(await connect(), isTrue);
      final old = factory.created.single;
      old.open = false;
      expect(await connect(), isTrue);
      old.recover();
      expect(factory.created.where((t) => t.isOpen()).length, 1);
      expect(parts.connections.relays.length, 1);
      await manager.closeAllTransports();
      old.recover();
      expect(factory.created.where((t) => t.isOpen()), isEmpty);
      expect(parts.connections.relays, isEmpty);
    },
  );

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
    'callbacks from retired transport cannot mutate current ownership',
    () async {
      await connect();
      final old = factory.created.single..open = false;
      await connect();
      final current = parts.connections.relays[key]!;
      current.stats.openRequestIds.add('live-request');
      final errors = current.stats.connectionErrors;
      old.disconnect?.call(1006, null, 'late disconnect');
      old.reconnect?.call();
      expect(current.stats.openRequestIds, {'live-request'});
      expect(current.stats.connectionErrors, errors);
      await pumpEventQueue();
      expect(allReplays(), 0);
      await manager.closeAllTransports();
      old.reconnect?.call();
      await pumpEventQueue();
      expect(allReplays(), 0);
      expect(parts.connections.relays, isEmpty);
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
      transport.reconnect?.call();
      expect(parts.connections.relays, isEmpty);
      expect(transport.closed, isTrue);
      await pumpEventQueue();
      expect(allReplays(), 0);
    },
  );

  test(
    'a reconnect of the current transport replays its subscriptions',
    () async {
      await connect();

      factory.created.single.reconnect?.call();
      await pumpEventQueue();

      expect(replays(factory.created.single), 1);
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
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
