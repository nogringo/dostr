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

  test('refuses unclean and blocked urls without opening anything', () async {
    manager.blockedRelays.add('wss://blocked.example');

    expect(await manager.connectRelay(dirtyUrl: 'https://not.a.relay'), (
      connected: false,
      error: 'unclean url',
    ));
    expect(await manager.connectRelay(dirtyUrl: 'wss://blocked.example/'), (
      connected: false,
      error: 'relay is blocked',
    ));
    expect(manager.connectivities, isEmpty);
  });

  test('connects to a relay with a null error', () async {
    final relay = await startRelay();

    expect(await manager.connectRelay(dirtyUrl: relay.url), (
      connected: true,
      error: null,
    ));
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

  test('closeConnection forgets the connection for good', () async {
    final relay = await startRelay();
    await manager.connectRelay(dirtyUrl: relay.url);

    await manager.closeConnection(RelayConnectionKey.anonymous(relay.url));

    expect(manager.connectivities, isEmpty);
    await eventually(() => relay.openClients.isEmpty);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(relay.clients, hasLength(1));
  });

  test('reconnects on its own once the relay drops the socket', () async {
    final relay = await startRelay();
    await manager.connectRelay(dirtyUrl: relay.url);

    await relay.dropConnections();

    await eventually(
      () => relay.openClients.length == 1 && relay.clients.length == 2,
      timeout: const Duration(seconds: 10),
    );
    await eventually(() => manager.isRelayConnected(relay.url));
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
