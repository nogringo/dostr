import 'dart:io';

import 'package:dostr_core/dostr_core.dart';
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

  tearDown(() => manager.dispose());

  test('connects once, however many callers ask at once', () async {
    final relay = await startRelay();

    final results = await Future.wait([
      for (var i = 0; i < 3; i++) manager.connectRelay(relay.url),
    ]);

    expect(results.map((r) => r.connected), [true, true, true]);
    expect(relay.clients, hasLength(1));
    expect(
      manager
              .connectivities[RelayConnectionKey.anonymous(relay.url)]
              ?.isConnected ??
          false,
      isTrue,
    );
  });

  test('every caller of a failed connect learns why it failed', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();

    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        manager.connectRelay(
          RelayUrl.parse('ws://127.0.0.1:$port'),
          connectTimeout: const Duration(milliseconds: 500),
        ),
    ]);

    for (final result in results) {
      expect(result.connected, isFalse);
      expect(result.failure?.kind, RelayFailureKind.unreachable);
      expect(result.failure?.detail, contains('SocketException'));
    }
  });

  test('refuses a blocked url without opening anything', () async {
    await manager.blockRelay(RelayUrl.parse('wss://blocked.example'));

    expect(
      await manager.connectRelay(RelayUrl.parse('wss://blocked.example/')),
      (connected: false, failure: const RelayFailure(RelayFailureKind.blocked)),
    );
    expect(manager.connectivities, isEmpty);
  });

  test('blocking a relay closes its connections until unblocked', () async {
    final relay = await startRelay(challengeOnConnect: false);
    await manager.connectRelay(relay.url);
    await manager.openConnectionAs(relay.url, fakeAccount(alice));

    await manager.blockRelay(relay.url);

    expect(manager.connectivities, isEmpty);
    expect(manager.blockedRelays, {relay.url});
    expect(() => manager.blockedRelays.clear(), throwsUnsupportedError);
    expect(
      (await manager.connectRelay(relay.url)).failure?.kind,
      RelayFailureKind.blocked,
    );

    manager.unblockRelay(relay.url);

    expect(await manager.connectRelay(relay.url), (
      connected: true,
      failure: null,
    ));
  });

  test('connects to a relay with a null failure', () async {
    final relay = await startRelay();

    expect(await manager.connectRelay(relay.url), (
      connected: true,
      failure: null,
    ));
  });

  test('closeConnectionsTo closes the anonymous and bound connections '
      'to one relay only', () async {
    final relay = await startRelay(challengeOnConnect: false);
    final other = await startRelay();
    await manager.connectRelay(relay.url);
    await manager.openConnectionAs(relay.url, fakeAccount(alice));
    await manager.connectRelay(other.url);
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

    await manager.connectRelay(relay.url);

    await eventually(
      () =>
          updates.isNotEmpty &&
          updates.last.any((c) => c.key.url == relay.url && c.isConnected),
    );
    await subscription.cancel();
  });

  test('reports a connection as it connects, opens and goes, and REQs on it '
      'leave its connectivity alone', () async {
    final relay = await startRelay();
    final reqs = RelayReqs(
      relayManager: manager,
      eventVerifier: FakeVerifier(),
    );
    final updates = <List<({bool connected, bool connecting})>>[];
    final subscription = manager.relayConnectivityChanges.listen(
      (connections) => updates.add([
        for (final c in connections)
          (connected: c.isConnected, connecting: c.isConnecting),
      ]),
    );

    await manager.connectRelay(relay.url);
    for (var i = 0; i < 3; i++) {
      await reqs.req(relays: {relay.url: notes}).done;
    }
    await manager.closeConnectionsTo(relay.url);
    await pumpEventQueue();

    expect(updates, [
      [(connected: false, connecting: true)],
      [(connected: true, connecting: false)],
      isEmpty,
    ]);
    await subscription.cancel();
  });

  test('hands out connections as they stood when read', () async {
    final relay = await startRelay();
    final key = RelayConnectionKey.anonymous(relay.url);
    final changes = <List<RelayConnectivity>>[];
    final subscription = manager.relayConnectivityChanges.listen(changes.add);
    await manager.connectRelay(relay.url);
    final connected = manager.connectivities[key]!;

    await manager.closeConnection(key);
    await pumpEventQueue();

    expect(connected.isConnected, isTrue);
    expect(changes.first.single.isConnecting, isTrue);
    await subscription.cancel();
  });

  test('closeConnection forgets the connection for good', () async {
    final relay = await startRelay();
    await manager.connectRelay(relay.url);

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
    await manager.connectRelay(relay.url);

    await relay.dropConnections();

    await eventually(
      () => relay.openClients.length == 1 && relay.clients.length == 2,
      timeout: const Duration(seconds: 10),
    );
    await eventually(
      () =>
          manager
              .connectivities[RelayConnectionKey.anonymous(relay.url)]
              ?.isConnected ??
          false,
    );
  });

  test('forgets a dropped socket nothing uses', () async {
    final relay = await startRelay();
    await manager.connectRelay(relay.url);

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

    expect(
      manager
              .connectivities[RelayConnectionKey.anonymous(busy.url)]
              ?.isConnected ??
          false,
      isTrue,
    );
    expect(
      manager
              .connectivities[RelayConnectionKey.anonymous(idle.url)]
              ?.isConnected ??
          false,
      isFalse,
    );
    await subscription.close();
  });

  test('hands what it does not handle to protocol handlers', () async {
    final relay = await startRelay();
    final recorder = _Recorder();
    manager.addProtocolHandler(recorder);
    await manager.connectRelay(relay.url);
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
    await manager.connectRelay(relay.url);

    manager.send(RelayConnectionKey.anonymous(relay.url), [
      'NEG-OPEN',
      'neg-1',
      {
        'kinds': [1],
      },
      '6100',
    ]);
    manager.send(
      RelayConnectionKey.anonymous(RelayUrl.parse('wss://unknown.example')),
      ['NEG-CLOSE', 'neg-2'],
    );

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

  group('dispose', () {
    test('ends the REQs and publishes in flight, and the connectivity '
        'changes', () async {
      final relay = await startRelay(answerEvents: false);
      final reqs = RelayReqs(
        relayManager: manager,
        eventVerifier: FakeVerifier(),
      );
      final changesDone = manager.relayConnectivityChanges.drain<void>();
      final subscription = reqs.req(
        relays: {relay.url: notes},
        closeOnEose: false,
      );
      final event = signedEvent(content: 'unanswered');
      final publish = RelayPublishes(relayManager: manager).publish(
        event,
        relays: [relay.url],
        timeout: const Duration(seconds: 30),
      );
      await eventually(() => relay.received('EVENT').isNotEmpty);

      await manager.dispose();

      expect(
        (await subscription.done)[relay.url]?.status,
        RelayRequestStatus.disconnected,
      );
      expect(
        (await publish.done)[relay.url]?.failure?.kind,
        RelayFailureKind.connectionLost,
      );
      await changesDone;
      expect(manager.connectivities, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('refuses to open anything afterwards', () async {
      final relay = await startRelay();
      final reqs = RelayReqs(
        relayManager: manager,
        eventVerifier: FakeVerifier(),
      );
      final publishes = RelayPublishes(relayManager: manager);

      await manager.dispose();

      expect(() => manager.connectRelay(relay.url), throwsStateError);
      expect(
        () => manager.openConnectionAs(relay.url, fakeAccount(alice)),
        throwsStateError,
      );
      expect(() => reqs.req(relays: {relay.url: notes}), throwsStateError);
      expect(
        () => publishes.publish(signedEvent(), relays: [relay.url]),
        throwsStateError,
      );
      expect(relay.clients, isEmpty);
    });
  });
}
