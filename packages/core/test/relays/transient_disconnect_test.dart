import 'dart:async';
import 'dart:io';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/relay_manager_parts.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

/// A real transport whose socket can be cut the way a lost network does: its
/// stream ends and it never comes back.
class _FlakyTransport implements NostrTransport {
  _FlakyTransport(this._inner);

  final NostrTransport _inner;
  final StreamController _out = StreamController();
  StreamSubscription? _innerSubscription;
  bool _dropped = false;

  void dropConnection() {
    _dropped = true;
    _innerSubscription?.cancel();
    _inner.close();
    _out.close();
  }

  @override
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) {
    _innerSubscription = _inner.listen(
      _out.add,
      onError: _out.addError,
      onDone: _out.close,
    );
    return _out.stream.listen(onData, onError: onError, onDone: onDone);
  }

  @override
  Future<void> close() async {
    await _innerSubscription?.cancel();
    if (!_out.isClosed) await _out.close();
    await _inner.close();
  }

  @override
  Future<void> get ready => _inner.ready;

  @override
  bool get isOpen => !_dropped && _inner.isOpen;

  @override
  void send(dynamic data) {
    if (!_dropped) _inner.send(data);
  }

  @override
  int? get closeCode => _dropped ? 1006 : _inner.closeCode;

  @override
  String? get closeReason => _dropped ? "connection lost" : _inner.closeReason;
}

/// What a socket opened during an outage gets: a refusal.
class _RefusedTransport implements NostrTransport {
  final _out = StreamController();

  @override
  Future<void> get ready =>
      Future.error(const SocketException("network is down"));

  @override
  bool get isOpen => false;

  @override
  Future<void> close() async {
    if (!_out.isClosed) await _out.close();
  }

  @override
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) => _out.stream.listen(onData, onError: onError, onDone: onDone);

  @override
  void send(dynamic data) {}

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _FlakyTransportFactory {
  final _inner = webSocketTransportFactory();
  final List<_FlakyTransport> created = [];

  /// refuses new sockets while set
  bool down = false;

  /// sockets refused so far
  int refused = 0;

  NostrTransport call(RelayUrl url) {
    if (down) {
      refused++;
      return _RefusedTransport();
    }
    final transport = _FlakyTransport(_inner(url));
    created.add(transport);
    return transport;
  }
}

void main() {
  late NostrSigner account;
  late FakeAuthAccounts accounts;

  setUp(() {
    account = fakeAccount(alice);
    accounts = FakeAuthAccounts()
      ..accounts[alice] = account
      ..loggedPubkey = alice;
  });

  int acceptedAuths(MockRelay relay) =>
      relay.clients.where((client) => client.authenticatedAs != null).length;

  test('an authentication does not survive a dropped socket', () async {
    final relay = await startRelay(requireAuthForRequests: true);

    final factory = _FlakyTransportFactory();
    final manager = newRelayManager(
      transportFactory: factory.call,
      accounts: accounts,
    );
    addTearDown(manager.dispose);

    final connectivity = await manager.openConnectionAs(relay.url, account);
    manager.addProtocolHandler(ClaimConnections({connectivity!.key}));
    expect(await manager.authenticateConnection(connectivity.key), true);
    expect(acceptedAuths(relay), 1);

    factory.down = true;
    factory.created.last.dropConnection();

    expect(
      manager.connectivities[connectivity.key]?.isConnected ?? false,
      false,
    );
    expect(
      await manager.authenticateConnection(connectivity.key),
      false,
      reason:
          'the connection is down, so it cannot still claim the AUTH the relay '
          'accepted on it',
    );

    factory.down = false;
    await _waitUntil(
      () => manager.connectivities[connectivity.key]?.isConnected ?? false,
    );
    expect(await manager.authenticateConnection(connectivity.key), true);
    expect(
      acceptedAuths(relay),
      2,
      reason: 'the new socket has to authenticate on its own',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('an in-flight AUTH fails with the socket it was sent on', () async {
    final relay = await startRelay(
      requireAuthForRequests: true,
      answerAuth: false,
    );

    final factory = _FlakyTransportFactory();
    final manager = RelayManager(
      nostrTransportFactory: factory.call,
      accounts: accounts,
      authCallbackTimeout: const Duration(seconds: 10),
    );
    addTearDown(manager.dispose);

    final connectivity = await manager.openConnectionAs(relay.url, account);
    final authenticating = manager.authenticateConnection(connectivity!.key);

    await _waitUntil(() => relay.received('AUTH').isNotEmpty);

    final elapsed = Stopwatch()..start();
    factory.down = true;
    factory.created.last.dropConnection();
    expect(await authenticating, false);
    elapsed.stop();

    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason:
          'the AUTH waited for its callback timeout instead of failing with '
          'the socket it was sent on',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'a subscription replayed after a dropped socket is counted once',
    () async {
      final subscribed = await _subscribeOnFlakyRelay();

      subscribed.factory.down = true;
      subscribed.transport.dropConnection();
      await _waitUntil(() => subscribed.factory.refused >= 1);
      expect(
        subscribed.openRequests,
        0,
        reason: 'the requests died with the socket that carried them',
      );

      subscribed.factory.down = false;
      await _waitUntil(() => subscribed.connectivity.isConnected);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        subscribed.openRequests,
        1,
        reason:
            'the replayed subscription was counted on top of the one the dead '
            'socket carried',
      );

      await subscribed.req.close();
      await _waitUntil(() => subscribed.openRequests == 0);

      await subscribed.tearDown();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a subscription closed during an outage is not replayed', () async {
    final subscribed = await _subscribeOnFlakyRelay();

    subscribed.factory.down = true;
    subscribed.transport.dropConnection();
    await _waitUntil(() => subscribed.factory.refused >= 1);
    subscribed.manager.send(subscribed.connectivity.key, ['CLOSE', _subId]);
    await subscribed.req.close();

    subscribed.factory.down = false;
    await _waitUntil(() => subscribed.connectivity.isConnected);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      subscribed.openRequests,
      0,
      reason: 'a subscription closed while the relay was unreachable came back',
    );

    await subscribed.tearDown();
  }, timeout: const Timeout(Duration(seconds: 60)));

  for (final closeOnEose in [false, true]) {
    final kind = closeOnEose ? 'query' : 'subscription';
    test(
      'a $kind opened while its connection comes back goes out once it is back',
      () async {
        final subscribed = await _subscribeOnFlakyRelay();
        final url = subscribed.key.url;

        subscribed.factory.down = true;
        subscribed.transport.dropConnection();
        await _waitUntil(
          () =>
              subscribed.factory.refused >= 1 &&
              !subscribed.connectivity.isConnecting,
        );

        final opened =
            RelayReqs(
              relayManager: subscribed.manager,
              eventVerifier: FakeVerifier(),
            ).req(
              relays: {
                url: [
                  Filter(kinds: [Nip01Event.kTextNoteKind]),
                ],
              },
              closeOnEose: closeOnEose,
            );
        opened.events.listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(opened.outcomes[url]?.status, RelayRequestStatus.pending);

        subscribed.factory.down = false;
        await _waitUntil(
          () => opened.outcomes[url]?.status == RelayRequestStatus.eose,
        );
        expect(subscribed.relayReceivedReq(opened.id), isTrue);

        await opened.close();
        await subscribed.tearDown();
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  test('a query does not end without a relay that comes back', () async {
    final subscribed = await _subscribeOnFlakyRelay();
    final flaky = subscribed.key;
    final flakyTransport = subscribed.transport;
    final steady = await startRelay();
    await subscribed.manager.connectRelay(steady.url);

    subscribed.factory.down = true;
    flakyTransport.dropConnection();
    await _waitUntil(() => subscribed.factory.refused >= 1);

    final notes = [
      Filter(kinds: [Nip01Event.kTextNoteKind]),
    ];
    final query = RelayReqs(
      relayManager: subscribed.manager,
      eventVerifier: FakeVerifier(),
    ).req(relays: {flaky.url: notes, steady.url: notes});
    query.events.listen((_) {});
    await _waitUntil(
      () => query.outcomes[steady.url]?.status == RelayRequestStatus.eose,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(query.outcomes[flaky.url]?.status, RelayRequestStatus.pending);

    subscribed.factory.down = false;
    expect((await query.done)[flaky.url]?.status, RelayRequestStatus.eose);

    await subscribed.tearDown();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a publish sent while its connection comes back waits for it', () async {
    final subscribed = await _subscribeOnFlakyRelay();
    final url = subscribed.key.url;

    subscribed.factory.down = true;
    subscribed.transport.dropConnection();
    await _waitUntil(
      () =>
          subscribed.factory.refused >= 1 &&
          !subscribed.connectivity.isConnecting,
    );

    final event = signedEvent(content: 'while it comes back');
    final publish = RelayPublishes(
      relayManager: subscribed.manager,
    ).publish(event, relays: [url], timeout: const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(publish.outcomes[url]?.failure, isNull);

    subscribed.factory.down = false;
    final response = (await publish.done)[url]!;
    expect(response.accepted, isTrue);
    expect(subscribed.relayReceivedEvent(event.id), isTrue);

    await subscribed.tearDown();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'a publish over before its connection is back is not sent there',
    () async {
      final subscribed = await _subscribeOnFlakyRelay();
      final url = subscribed.key.url;

      subscribed.factory.down = true;
      subscribed.transport.dropConnection();
      await _waitUntil(
        () =>
            subscribed.factory.refused >= 1 &&
            !subscribed.connectivity.isConnecting,
      );

      final event = signedEvent(content: 'too late');
      final publish = RelayPublishes(relayManager: subscribed.manager).publish(
        event,
        relays: [url],
        timeout: const Duration(milliseconds: 300),
      );
      final response = (await publish.done)[url]!;
      expect(response.status, RelayPublishStatus.timedOut);

      subscribed.factory.down = false;
      await _waitUntil(() => subscribed.connectivity.isConnected);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(subscribed.relayReceivedEvent(event.id), isFalse);

      await subscribed.tearDown();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a connection whose work ended during an outage is forgotten', () async {
    final relay = await startRelay();
    final factory = _FlakyTransportFactory();
    final manager = RelayManager(nostrTransportFactory: factory.call);
    addTearDown(manager.dispose);
    final key = RelayConnectionKey.anonymous(relay.url);
    final claim = ClaimConnections({key});
    manager.addProtocolHandler(claim);
    await manager.connectRelay(relay.url);

    factory.down = true;
    factory.created.last.dropConnection();
    await _waitUntil(() => factory.refused >= 1);
    claim.keys.clear();

    await _waitUntil(() => manager.connectivities.isEmpty);
    factory.down = false;
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(factory.created, hasLength(1));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

const _subId = "sub";

class _SubscribedOnFlakyRelay {
  _SubscribedOnFlakyRelay(
    this.manager,
    this.key,
    this.factory,
    this._relay,
    this.req,
  );

  final RelayManager manager;
  final RelayConnectionKey key;
  final _FlakyTransportFactory factory;
  final MockRelay _relay;
  final RelayReq req;

  RelayConnectivity get connectivity => manager.connectivities[key]!;

  int get openRequests => _openRequests(manager, key);

  _FlakyTransport get transport => factory.created.last;

  bool relayReceivedReq(String id) =>
      _relay.received('REQ').any((message) => message[1] == id);

  bool relayReceivedEvent(String id) =>
      _relay.events.any((event) => event.id == id);

  Future<void> tearDown() async {
    await manager.dispose();
    await _relay.stop();
  }
}

/// Opens a connection carrying one subscription, counted as open on it
Future<_SubscribedOnFlakyRelay> _subscribeOnFlakyRelay() async {
  final relay = MockRelay();
  await relay.start();

  final factory = _FlakyTransportFactory();
  final manager = RelayManager(nostrTransportFactory: factory.call);
  await manager.connectRelay(relay.url);

  final connectionKey = RelayConnectionKey.anonymous(relay.url);
  final filters = [
    Filter(kinds: [Nip01Event.kTextNoteKind]),
  ];
  final req = RelayReqs(
    relayManager: manager,
    eventVerifier: FakeVerifier(),
  ).req(id: _subId, relays: {relay.url: filters}, closeOnEose: false);
  await _waitUntil(() => _openRequests(manager, connectionKey) == 1);

  return _SubscribedOnFlakyRelay(manager, connectionKey, factory, relay, req);
}

/// REQs written on the connection behind [key] and not closed since
int _openRequests(RelayManager manager, RelayConnectionKey key) =>
    relayManagerParts(manager).connections.relays[key]!.slots.written.length;

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('condition never became true');
}
