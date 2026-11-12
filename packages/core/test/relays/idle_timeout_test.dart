import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  final notes = [
    Filter(kinds: [1]),
  ];

  RelayManager manager({
    Duration? anonymous,
    Duration? authenticated,
    AuthAccounts? accounts,
  }) {
    final manager = RelayManager(
      nostrTransportFactory: WebSocketClientNostrTransportFactory(
        pingInterval: null,
      ),
      accounts: accounts,
      anonymousIdleTimeout: anonymous,
      authenticatedIdleTimeout: authenticated,
    );
    addTearDown(manager.closeAllTransports);
    return manager;
  }

  test('a connection with nothing to do closes after its timeout', () async {
    final relay = await startRelay();
    final relays = manager(anonymous: const Duration(milliseconds: 300));
    await relays.connectRelay(dirtyUrl: relay.url);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(relays.isRelayConnected(relay.url), isTrue);

    await eventually(() => relays.connectivities.isEmpty);
    await eventually(() => relay.openClients.isEmpty);
  });

  test(
    'a connection opened after the others closed is watched again',
    () async {
      final relay = await startRelay();
      final relays = manager(anonymous: const Duration(milliseconds: 200));
      await relays.connectRelay(dirtyUrl: relay.url);
      await eventually(() => relays.connectivities.isEmpty);

      await relays.connectRelay(dirtyUrl: relay.url);
      await eventually(() => relays.connectivities.isEmpty);
      expect(relay.clients, hasLength(2));
    },
  );

  test('a live subscription keeps its connection past the timeout', () async {
    final relay = await startRelay();
    final relays = manager(anonymous: const Duration(milliseconds: 200));
    final reqs = RelayReqs(relayManager: relays, eventVerifier: FakeVerifier());
    final subscription = reqs.req(
      relays: {relay.url: notes},
      closeOnEose: false,
    );
    await eventually(() => relay.activeSubscriptionCount == 1);

    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(relays.isRelayConnected(relay.url), isTrue);

    await subscription.close();
    await eventually(() => relays.connectivities.isEmpty);
  });

  test('requests in a row keep one connection open', () async {
    final relay = await startRelay();
    final relays = manager(anonymous: const Duration(milliseconds: 400));
    final reqs = RelayReqs(relayManager: relays, eventVerifier: FakeVerifier());

    for (var i = 0; i < 5; i++) {
      await reqs.req(relays: {relay.url: notes}).done;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    expect(relay.clients, hasLength(1));
    await eventually(() => relays.connectivities.isEmpty);
  });

  Future<(RelayManager, RelayConnectionKey, RelayConnectionKey)> connectBoth({
    Duration? anonymous,
    Duration? authenticated,
  }) async {
    final account = fakeAccount(alice);
    final accounts = FakeAuthAccounts()..accounts[alice] = account;
    final relay = await startRelay();
    final relays = manager(
      anonymous: anonymous,
      authenticated: authenticated,
      accounts: accounts,
    );
    await relays.connectRelay(dirtyUrl: relay.url);
    final bound = await relays.openConnectionAs(relay.url, account);
    return (relays, RelayConnectionKey.anonymous(relay.url), bound!.key);
  }

  test('a bound connection follows its own timeout', () async {
    final (relays, anonymous, bound) = await connectBoth(
      authenticated: const Duration(milliseconds: 200),
    );

    await eventually(() => !relays.connectivities.containsKey(bound));
    expect(relays.isConnectionOpen(anonymous), isTrue);
  });

  test('a null timeout keeps idle connections open', () async {
    final (relays, anonymous, bound) = await connectBoth(
      anonymous: const Duration(milliseconds: 200),
    );

    await eventually(() => !relays.connectivities.containsKey(anonymous));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(relays.isConnectionOpen(bound), isTrue);
  });

  test('rejects a timeout that is not positive', () {
    expect(
      () => RelayManager(
        nostrTransportFactory: WebSocketClientNostrTransportFactory(),
        anonymousIdleTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}
