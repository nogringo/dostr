import 'dart:io';

import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

class _Recorder extends RelayProtocolHandler {
  final messages = <List<dynamic>>[];
  final notices = <String>[];
  final closed = <String>[];

  @override
  bool onMessage(RelayConnectionKey key, List<dynamic> message) {
    if (message[0] != 'NEG-MSG') return false;
    messages.add(message);
    return true;
  }

  @override
  void onNotice(RelayConnectionKey key, String message) => notices.add(message);

  @override
  bool onClosed(
    RelayConnectionKey key,
    String subscriptionId,
    String? message,
  ) {
    if (subscriptionId != 'neg-1') return false;
    closed.add(subscriptionId);
    return true;
  }
}

void main() {
  late RelayManager manager;

  final notes = [
    Filter(kinds: [1]),
  ];

  setUp(() => manager = newRelayManager());

  tearDown(() => manager.closeAllTransports());

  test('connects once, however many callers ask at once', () async {
    final relay = await startRelay();

    final results = await Future.wait([
      for (var i = 0; i < 3; i++) manager.connectRelay(dirtyUrl: relay.url),
    ]);

    expect(results.map((r) => r.connected), [true, true, true]);
    expect(relay.clients, hasLength(1));
    expect(manager.isRelayConnected(relay.url), isTrue);
  });

  test('every caller of a failed connect learns why it failed', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();

    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        manager.connectRelay(
          dirtyUrl: 'ws://127.0.0.1:$port',
          connectTimeout: const Duration(milliseconds: 500),
        ),
    ]);

    for (final result in results) {
      expect(result.connected, isFalse);
      expect(result.failure?.kind, RelayFailureKind.unreachable);
      expect(result.failure?.detail, contains('SocketException'));
    }
  });

  test('refuses unclean and blocked urls without opening anything', () async {
    manager.blockedRelays.add('wss://blocked.example');

    expect(await manager.connectRelay(dirtyUrl: 'https://not.a.relay'), (
      connected: false,
      failure: const RelayFailure(RelayFailureKind.invalidUrl),
    ));
    expect(await manager.connectRelay(dirtyUrl: 'wss://blocked.example/'), (
      connected: false,
      failure: const RelayFailure(RelayFailureKind.blocked),
    ));
    expect(manager.connectivities, isEmpty);
  });

  test('connects to a relay with a null failure', () async {
    final relay = await startRelay();

    expect(await manager.connectRelay(dirtyUrl: relay.url), (
      connected: true,
      failure: null,
    ));
  });

  test('remembers when it last tried to connect', () async {
    final relay = await startRelay();
    await manager.connectRelay(dirtyUrl: relay.url);

    final connection =
        manager.connectivities[RelayConnectionKey.anonymous(relay.url)]!;
    expect(connection.relay.wasLastConnectTryLongerThanSeconds(120), isFalse);
  });

  test('closeConnectionsTo closes the anonymous and bound connections '
      'to one relay only', () async {
    final relay = await startRelay(challengeOnConnect: false);
    final other = await startRelay();
    await manager.connectRelay(dirtyUrl: relay.url);
    await manager.openConnectionAs(relay.url, fakeAccount(alice));
    await manager.connectRelay(dirtyUrl: other.url);
    expect(manager.connectivities, hasLength(3));

    await manager.closeConnectionsTo(relay.url);

    expect(manager.connectivities.keys, [
      RelayConnectionKey.anonymous(other.url),
    ]);
  });

  test('reports connectivity changes', () async {
    final relay = await startRelay();
    final updates = <List<RelayConnectivity>>[];
    final subscription = manager.relayConnectivityChanges.listen(updates.add);

    await manager.connectRelay(dirtyUrl: relay.url);

    await eventually(
      () =>
          updates.isNotEmpty &&
          updates.last.any((c) => c.url == relay.url && c.isConnected),
    );
    await subscription.cancel();
  });

  test('closing forgets a connection whose transport was reset', () async {
    final relay = await startRelay();
    await manager.connectRelay(dirtyUrl: relay.url);

    await manager.resetConnectionsTo(relay.url);
    await manager.closeAllTransports();

    expect(manager.connectivities, isEmpty);
  });

  test('closeConnection forgets the connection for good', () async {
    final relay = await startRelay();
    await manager.connectRelay(dirtyUrl: relay.url);

    await manager.closeConnection(RelayConnectionKey.anonymous(relay.url));

    expect(manager.connectivities, isEmpty);
    await eventually(() => relay.openClients.isEmpty);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(relay.clients, hasLength(1));
  });

  test('reconnects on its own once the relay drops a socket in use', () async {
    final relay = await startRelay();
    final key = RelayConnectionKey.anonymous(relay.url);
    manager.addProtocolHandler(ClaimConnections({key}));
    await manager.connectRelay(dirtyUrl: relay.url);
    final stats = manager.connectivities[key]!.stats;
    expect(stats.connections, 1);

    await relay.dropConnections();

    await eventually(
      () => relay.openClients.length == 1 && relay.clients.length == 2,
      timeout: const Duration(seconds: 10),
    );
    await eventually(() => manager.isRelayConnected(relay.url));
    expect(stats.connections, 2);
  });

  test('forgets a dropped socket nothing uses', () async {
    final relay = await startRelay();
    await manager.connectRelay(dirtyUrl: relay.url);

    await relay.dropConnections();

    await eventually(() => manager.connectivities.isEmpty);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(relay.clients, hasLength(1));
  });

  test('closeIdleConnections keeps the connections still in use', () async {
    final busy = await startRelay();
    final idle = await startRelay();
    final reqs = RelayReqs(
      relayManager: manager,
      eventVerifier: FakeVerifier(),
    );
    final subscription = reqs.req(
      relays: {busy.url: notes},
      closeOnEose: false,
    );
    subscription.events.listen((_) {});
    await reqs.req(relays: {idle.url: notes}).done;
    await eventually(
      () => busy.openClients.any(
        (c) => c.subscriptions.containsKey(subscription.id),
      ),
    );

    await manager.closeIdleConnections();

    expect(manager.isRelayConnected(busy.url), isTrue);
    expect(manager.isRelayConnected(idle.url), isFalse);
    await subscription.close();
  });

  test('closeIdleConnections ignores work that never picked a relay', () async {
    final idle = await startRelay();
    final reqs = RelayReqs(
      relayManager: manager,
      eventVerifier: FakeVerifier(),
    );
    final forgotten = reqs.req();
    final publishes = RelayPublishes(relayManager: manager);
    final unsigned = publishes.open(signedEvent(content: 'never signed'));
    await manager.connectRelay(dirtyUrl: idle.url);

    await manager.closeIdleConnections();

    expect(manager.isRelayConnected(idle.url), isFalse);
    await forgotten.close();
    unsigned.fail(StateError('test over'));
    await unsigned.done.catchError((_) => <String, RelayBroadcastResponse>{});
  });

  test('hands what it does not handle to protocol handlers', () async {
    final relay = await startRelay();
    final recorder = _Recorder();
    manager.addProtocolHandler(recorder);
    await manager.connectRelay(dirtyUrl: relay.url);
    await eventually(() => relay.openClients.isNotEmpty);

    relay.sendToAll(['NEG-MSG', 'neg-1', 'abcd']);
    relay.sendToAll(['NOTICE', 'hello']);
    relay.sendToAll(['CLOSED', 'neg-1', 'done']);
    await eventually(
      () =>
          recorder.messages.isNotEmpty &&
          recorder.notices.isNotEmpty &&
          recorder.closed.isNotEmpty,
    );
    expect(recorder.messages.single, ['NEG-MSG', 'neg-1', 'abcd']);
    expect(recorder.notices, ['hello']);

    manager.removeProtocolHandler(recorder);
    relay.sendToAll(['NEG-MSG', 'neg-1', 'efgh']);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(recorder.messages, hasLength(1));
  });

  test('sends a raw message on the connection of a key', () async {
    final relay = await startRelay();
    await manager.connectRelay(dirtyUrl: relay.url);

    manager.send(RelayConnectionKey.anonymous(relay.url), [
      'NEG-OPEN',
      'neg-1',
      {
        'kinds': [1],
      },
      '6100',
    ]);
    manager.send(RelayConnectionKey.anonymous('wss://unknown.example'), [
      'NEG-CLOSE',
      'neg-2',
    ]);

    await eventually(() => relay.received('NEG-OPEN').isNotEmpty);
    expect(relay.received('NEG-OPEN').single, [
      'NEG-OPEN',
      'neg-1',
      {
        'kinds': [1],
      },
      '6100',
    ]);
  });
}
