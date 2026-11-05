import 'dart:async';
import 'dart:io';

import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:ndk_core/domain_layer/repositories/nostr_transport.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'package:ndk/entities.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import '../mocks/mock_event_verifier.dart';
import '../mocks/mock_relay.dart';

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
  bool isOpen() => !_dropped && _inner.isOpen();

  @override
  bool isConnecting() => !_dropped && _inner.isConnecting();

  @override
  void send(data) {
    if (!_dropped) _inner.send(data);
  }

  @override
  int? closeCode() => _dropped ? 1006 : _inner.closeCode();

  @override
  String? closeReason() => _dropped ? "connection lost" : _inner.closeReason();
}

/// What a socket opened during an outage gets: a refusal.
class _RefusedTransport implements NostrTransport {
  final _out = StreamController();

  @override
  Future<void> get ready =>
      Future.error(const SocketException("network is down"));

  @override
  bool isOpen() => false;

  @override
  bool isConnecting() => false;

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
  void send(data) {}

  @override
  int? closeCode() => null;

  @override
  String? closeReason() => null;
}

class _FlakyTransportFactory implements NostrTransportFactory {
  final _inner = WebSocketClientNostrTransportFactory();
  final List<_FlakyTransport> created = [];

  /// refuses new sockets while set
  bool down = false;

  @override
  NostrTransport call(String url) {
    if (down) return _RefusedTransport();
    final transport = _FlakyTransport(_inner(url));
    created.add(transport);
    return transport;
  }
}

void main() {
  late KeyPair key;
  late Accounts accounts;

  setUp(() {
    key = Bip340.generatePrivateKey();
    accounts = Accounts(const Bip340EventSignerFactory());
    accounts.loginPrivateKey(pubkey: key.publicKey, privkey: key.privateKey!);
  });

  test('an authentication does not survive a dropped socket', () async {
    final relay = MockRelay(
      name: "relay requiring auth",
      requireAuthForRequests: true,
      signEvents: false,
      challengePerConnection: true,
    );
    await relay.startServer();

    final factory = _FlakyTransportFactory();
    final manager = RelayManager(
      bootstrapRelays: [],
      nostrTransportFactory: factory,
      accounts: accounts,
    );

    final account = accounts.getLoggedAccount()!;
    final connectivity = await manager.openConnectionAs(relay.url, account);
    expect(await manager.authenticateConnection(connectivity!.key), true);
    expect(relay.acceptedAuths, 1);

    factory.down = true;
    factory.created.last.dropConnection();

    expect(manager.isConnectionOpen(connectivity.key), false);
    expect(
      await manager.authenticateConnection(connectivity.key),
      false,
      reason:
          'the connection is down, so it cannot still claim the AUTH the relay '
          'accepted on it',
    );

    factory.down = false;
    await _waitUntil(() => manager.isConnectionOpen(connectivity.key));
    expect(await manager.authenticateConnection(connectivity.key), true);
    expect(
      relay.acceptedAuths,
      2,
      reason: 'the new socket has to authenticate on its own',
    );

    await manager.closeAllTransports();
    await relay.stopServer();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('an in-flight AUTH fails with the socket it was sent on', () async {
    final relay = MockRelay(
      name: "relay going quiet mid auth",
      requireAuthForRequests: true,
      signEvents: false,
      challengePerConnection: true,
      silenceFirstAuths: 1,
    );
    await relay.startServer();

    final factory = _FlakyTransportFactory();
    final manager = RelayManager(
      bootstrapRelays: [],
      nostrTransportFactory: factory,
      accounts: accounts,
      authCallbackTimeout: const Duration(seconds: 10),
    );

    final account = accounts.getLoggedAccount()!;
    final connectivity = await manager.openConnectionAs(relay.url, account);
    final authenticating = manager.authenticateConnection(connectivity!.key);

    while (relay.receivedAuths < 1) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

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

    await manager.closeAllTransports();
    await relay.stopServer();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'a subscription replayed after a dropped socket is counted once',
    () async {
      final subscribed = await _subscribeOnFlakyRelay();
      final connectivity = subscribed.connectivity;

      subscribed.factory.down = true;
      subscribed.transport.dropConnection();
      await _waitUntil(() => connectivity.stats.connectionErrors >= 1);
      expect(
        connectivity.stats.activeRequests,
        0,
        reason: 'the requests died with the socket that carried them',
      );

      subscribed.factory.down = false;
      await _waitUntil(() => connectivity.isConnected);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        connectivity.stats.activeRequests,
        1,
        reason:
            'the replayed subscription was counted on top of the one the dead '
            'socket carried',
      );

      await subscribed.req.close();
      await _waitUntil(() => connectivity.stats.activeRequests == 0);

      await subscribed.tearDown();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a subscription closed during an outage is not replayed', () async {
    final subscribed = await _subscribeOnFlakyRelay();
    final connectivity = subscribed.connectivity;

    subscribed.factory.down = true;
    subscribed.transport.dropConnection();
    await _waitUntil(() => connectivity.stats.connectionErrors >= 1);
    subscribed.manager.send(connectivity.key, ['CLOSE', _subId]);
    await subscribed.req.close();

    subscribed.factory.down = false;
    await _waitUntil(() => connectivity.isConnected);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      connectivity.stats.activeRequests,
      0,
      reason: 'a subscription closed while the relay was unreachable came back',
    );

    await subscribed.tearDown();
  }, timeout: const Timeout(Duration(seconds: 60)));
}

const _subId = "sub";

class _SubscribedOnFlakyRelay {
  _SubscribedOnFlakyRelay(
    this.manager,
    this.connectivity,
    this.factory,
    this._relay,
    this.req,
  );

  final RelayManager manager;
  final RelayConnectivity connectivity;
  final _FlakyTransportFactory factory;
  final MockRelay _relay;
  final RelayReq req;

  _FlakyTransport get transport => factory.created.last;

  Future<void> tearDown() async {
    await manager.closeAllTransports();
    await _relay.stopServer();
  }
}

/// Opens a connection carrying one subscription, counted as open on it
Future<_SubscribedOnFlakyRelay> _subscribeOnFlakyRelay() async {
  final relay = MockRelay(name: "relay", signEvents: false);
  await relay.startServer();

  final factory = _FlakyTransportFactory();
  final manager = RelayManager(
    bootstrapRelays: [],
    nostrTransportFactory: factory,
  );
  await manager.connectRelay(dirtyUrl: relay.url);

  final connectionKey = RelayConnectionKey.anonymous(relay.url);
  final connectivity = manager.connectivities[connectionKey]!;
  final filters = [
    Filter(kinds: [Nip01Event.kTextNodeKind]),
  ];
  final req = RelayReqs(
    relayManager: manager,
    eventVerifier: MockEventVerifier(),
  ).req(id: _subId, relays: {relay.url: filters}, closeOnEose: false);
  await _waitUntil(() => connectivity.stats.activeRequests == 1);

  return _SubscribedOnFlakyRelay(manager, connectivity, factory, relay, req);
}

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
