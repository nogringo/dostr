import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

/// A real transport whose stream can be made to end with an error, the way a
/// socket that breaks instead of closing cleanly does.
class _FaultyTransport implements NostrTransport {
  _FaultyTransport(this._inner);

  final NostrTransport _inner;
  final StreamController _out = StreamController();
  StreamSubscription? _innerSubscription;

  void breakStream() => _out.addError(StateError("socket blew up"));

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
    _innerSubscription = null;
    if (!_out.isClosed) {
      await _out.close();
    }
    await _inner.close();
  }

  @override
  Future<void> get ready => _inner.ready;

  @override
  bool isOpen() => _inner.isOpen();

  @override
  bool isConnecting() => _inner.isConnecting();

  @override
  void send(data) => _inner.send(data);

  @override
  int? closeCode() => _inner.closeCode();

  @override
  String? closeReason() => _inner.closeReason();
}

class _FaultyTransportFactory implements NostrTransportFactory {
  final _inner = WebSocketClientNostrTransportFactory();
  final List<_FaultyTransport> created = [];

  @override
  NostrTransport call(String url) {
    final transport = _FaultyTransport(_inner(url));
    created.add(transport);
    return transport;
  }
}

void main() {
  test('a socket that ends with an error reconnects', () async {
    final relay = await startRelay();

    final factory = _FaultyTransportFactory();
    final manager = newRelayManager(transportFactory: factory);
    addTearDown(manager.closeAllTransports);
    final key = RelayConnectionKey.anonymous(relay.url);
    manager.addProtocolHandler(ClaimConnections({key}));
    await manager.connectRelay(dirtyUrl: relay.url);

    final connectivity = manager.connectivities[key]!;
    expect(connectivity.stats.connections, 1);

    factory.created.last.breakStream();

    await eventually(
      () => connectivity.stats.connections >= 2,
      timeout: const Duration(seconds: 15),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'an authentication does not survive a socket that ended with an error',
    () async {
      final account = fakeAccount(alice);
      final accounts = FakeAuthAccounts()
        ..accounts[alice] = account
        ..loggedPubkey = alice;
      final relay = await startRelay(requireAuthForRequests: true);

      final factory = _FaultyTransportFactory();
      final manager = newRelayManager(
        transportFactory: factory,
        accounts: accounts,
      );
      addTearDown(manager.closeAllTransports);

      final connectivity = await manager.openConnectionAs(relay.url, account);
      expect(connectivity, isNotNull);
      manager.addProtocolHandler(ClaimConnections({connectivity!.key}));
      expect(await manager.authenticateConnection(connectivity.key), true);
      int acceptedAuths() => relay.clients
          .where((client) => client.authenticatedAs != null)
          .length;
      expect(acceptedAuths(), 1);

      factory.created.last.breakStream();

      // the replacement socket must answer its own challenge, not keep the
      // AUTH the relay accepted on the socket that broke
      await eventually(
        () => acceptedAuths() == 2,
        timeout: const Duration(seconds: 15),
      );
      expect(
        relay.openClients.where((client) => client.authenticatedAs == alice),
        hasLength(1),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a relay that drops every socket once it gets a REQ is reconnected '
      'on a backoff', () async {
    final relay = await startRelay();
    relay.onMessage = (client, message) {
      if (message.first != 'REQ') return false;
      client.close();
      return true;
    };
    final manager = newRelayManager();
    addTearDown(manager.closeAllTransports);
    final reqs = RelayReqs(
      relayManager: manager,
      eventVerifier: FakeVerifier(),
    );

    final req = reqs.req(
      relays: {
        relay.url: [
          Filter(kinds: [1]),
        ],
      },
      closeOnEose: false,
    );
    await Future<void>.delayed(const Duration(seconds: 2));

    // right away, then after 0.5 and 1 more seconds
    expect(relay.clients, hasLength(inInclusiveRange(3, 5)));
    await req.close();
  });
}
