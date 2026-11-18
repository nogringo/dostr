import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  late RelayManager manager;
  late RelayReqs reqs;
  late RelayPublishes publishes;

  final notes = [
    Filter(kinds: [1]),
  ];

  void build(RelayManager relayManager) {
    manager = relayManager;
    reqs = RelayReqs(relayManager: manager, eventVerifier: FakeVerifier());
    publishes = RelayPublishes(relayManager: manager);
  }

  setUp(() => build(newRelayManager()));

  tearDown(() => manager.dispose());

  bool subscribed(MockRelay relay, RelayReq req) =>
      relay.openClients.any((c) => c.subscriptions.containsKey(req.id));

  RelayRequestStatus? status(RelayReq req, MockRelay relay) =>
      req.outcomes[relay.url]?.status;

  Future<RelayReq> subscribe(
    MockRelay relay,
    List<String> received, {
    AuthPolicy? auth,
  }) async {
    final req = reqs.req(
      relays: {relay.url: notes},
      closeOnEose: false,
      auth: auth,
    );
    req.events.listen((event) => received.add(event.event.content));
    addTearDown(req.close);
    await eventually(() => subscribed(relay, req));
    return req;
  }

  test('a subscription waits for resume, then goes out again', () async {
    final relay = await startRelay();
    final received = <String>[];
    final req = await subscribe(relay, received);

    await manager.suspend();
    expect(manager.isSuspended, isTrue);
    await eventually(() => relay.openClients.isEmpty);
    relay.events.add(signedEvent(content: 'while away', createdAt: 1000));

    await manager.resume();
    expect(manager.isSuspended, isFalse);
    await eventually(() => received.contains('while away'));
    expect(subscribed(relay, req), isTrue);
    expect(relay.clients, hasLength(2));
  });

  test('no socket opens while suspended', () async {
    final relay = await startRelay();
    final req = await subscribe(relay, []);

    await manager.suspend();
    await manager.reconnectClosedConnections();
    final connected = await manager.connectRelay(relay.url);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(connected.connected, isFalse);
    expect(connected.failure?.kind, RelayFailureKind.connectionLost);
    expect(relay.clients, hasLength(1));
    expect(status(req, relay), isNot(RelayRequestStatus.disconnected));
  });

  test('a REQ opened while suspended goes out on resume', () async {
    final relay = await startRelay();
    relay.events.add(signedEvent(content: 'stored', createdAt: 1000));
    await manager.suspend();

    final req = reqs.req(relays: {relay.url: notes});
    final events = req.events.toList();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(relay.clients, isEmpty);

    await manager.resume();
    expect((await events).map((e) => e.event.content), ['stored']);
    expect(await req.done, {
      relay.url: const RelayRequestOutcome(RelayRequestStatus.eose),
    });
  });

  test('an EVENT left without its OK is sent again on resume', () async {
    final relay = await startRelay(answerEvents: false);
    final publish = publishes.publish(signedEvent(), relays: [relay.url]);
    await eventually(() => relay.received('EVENT').isNotEmpty);

    await manager.suspend();
    relay.answerEvents = true;
    await manager.resume();

    final outcomes = await publish.done;
    expect(outcomes[relay.url]?.status, RelayPublishStatus.accepted);
    expect(relay.received('EVENT'), hasLength(2));
  });

  test('a publish started while suspended goes out on resume', () async {
    final relay = await startRelay();
    await subscribe(relay, []);
    await manager.suspend();

    final publish = publishes.publish(signedEvent(), relays: [relay.url]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(relay.received('EVENT'), isEmpty);

    await manager.resume();
    final outcomes = await publish.done;
    expect(outcomes[relay.url]?.status, RelayPublishStatus.accepted);
  });

  test('a socket still opening when suspended waits for resume', () async {
    final relay = MockRelay();
    await relay.start(
      events: [signedEvent(content: 'stored', createdAt: 1000)],
      delayConnection: const Duration(milliseconds: 300),
    );
    addTearDown(relay.stop);
    final key = RelayConnectionKey.anonymous(relay.url);

    final req = reqs.req(relays: {relay.url: notes});
    final events = req.events.toList();
    await eventually(() => manager.connectivities[key]?.isConnecting ?? false);
    await manager.suspend();
    await eventually(
      () => !(manager.connectivities[key]?.isConnecting ?? true),
    );
    expect(status(req, relay), isNot(RelayRequestStatus.notSent));

    await manager.resume();
    expect((await events).map((e) => e.event.content), ['stored']);
  });

  test('a bound connection authenticates again on resume', () async {
    final relay = await startRelay(requireAuthForRequests: true);
    final req = await subscribe(
      relay,
      [],
      auth: AuthPolicy.require(fakeAccount(alice)),
    );
    expect(relay.acceptedAuths, 1);

    await manager.suspend();
    await manager.resume();

    await eventually(() => subscribed(relay, req));
    expect(relay.acceptedAuths, 2);
  });

  test('a suspension does not count toward reconnectGiveUpAfter', () async {
    await manager.dispose();
    build(
      RelayManager(
        nostrTransportFactory: webSocketTransportFactory(pingInterval: null),
        reconnectGiveUpAfter: const Duration(milliseconds: 200),
      ),
    );
    final relay = await startRelay();
    final req = await subscribe(relay, []);

    await manager.suspend();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(status(req, relay), isNot(RelayRequestStatus.disconnected));

    await manager.resume();
    await eventually(() => subscribed(relay, req));
  });

  test('suspend forgets the connections that carry nothing', () async {
    final relay = await startRelay();
    expect((await manager.connectRelay(relay.url)).connected, isTrue);

    await manager.suspend();

    expect(manager.connectivities, isEmpty);
    await manager.resume();
    expect(relay.clients, hasLength(1));
  });

  test('dispose ends what waited for resume', () async {
    final relay = await startRelay();
    final req = await subscribe(relay, []);
    await manager.suspend();
    final publish = publishes.publish(signedEvent(), relays: [relay.url]);

    await manager.dispose();

    expect((await publish.done)[relay.url]?.status, RelayPublishStatus.failed);
    expect(status(req, relay), RelayRequestStatus.disconnected);
  });
}
