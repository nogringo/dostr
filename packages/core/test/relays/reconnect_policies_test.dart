import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_mock_relay/dostr_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  final notes = [
    Filter(kinds: [1]),
  ];

  RelayManager manager({
    Duration unreachableRelayRetryAfter = defaultUnreachableRelayRetryAfter,
    Duration? reconnectGiveUpAfter = defaultReconnectGiveUpAfter,
  }) {
    final manager = RelayManager(
      nostrTransportFactory: webSocketTransportFactory(pingInterval: null),
      reconnectMaximumDelay: const Duration(milliseconds: 100),
      reconnectGiveUpAfter: reconnectGiveUpAfter,
      unreachableRelayRetryAfter: unreachableRelayRetryAfter,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  RelayReq req(RelayManager manager, RelayUrl url, {bool closeOnEose = true}) =>
      RelayReqs(
        relayManager: manager,
        eventVerifier: FakeVerifier(),
      ).req(relays: {url: notes}, closeOnEose: closeOnEose);

  group('a relay that could not be reached', () {
    Future<MockRelay> missedThenStarted(RelayManager manager) async {
      final relay = MockRelay();
      final attempt = await manager.connectRelay(
        relay.url,
        connectTimeout: const Duration(milliseconds: 100),
      );
      expect(attempt.connected, isFalse);
      await relay.start();
      addTearDown(relay.stop);
      return relay;
    }

    test('is left alone by a REQ for a while', () async {
      final relays = manager();
      final relay = await missedThenStarted(relays);

      final outcome = (await req(relays, relay.url).done)[relay.url]!;

      expect(outcome.status, RelayRequestStatus.notSent);
      expect(outcome.failure?.kind, RelayFailureKind.unreachable);
    });

    test('is tried again at once with a zero retry delay', () async {
      final relays = manager(unreachableRelayRetryAfter: Duration.zero);
      final relay = await missedThenStarted(relays);

      expect(await req(relays, relay.url).done, {
        relay.url: const RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });
  });

  test('a dropped connection is given up only with a give-up delay', () async {
    final relay = await startRelay();
    final givingUp = req(
      manager(reconnectGiveUpAfter: const Duration(milliseconds: 200)),
      relay.url,
      closeOnEose: false,
    );
    final keepingOn = req(
      manager(reconnectGiveUpAfter: null),
      relay.url,
      closeOnEose: false,
    );
    givingUp.events.listen(null);
    keepingOn.events.listen(null);
    bool caughtUp(RelayReq req) =>
        req.outcomes[relay.url]?.status == RelayRequestStatus.eose;
    await eventually(() => caughtUp(givingUp) && caughtUp(keepingOn));

    await relay.stop();
    await eventually(
      () =>
          givingUp.outcomes[relay.url]?.status ==
          RelayRequestStatus.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(caughtUp(keepingOn), isTrue);

    await relay.start();
    await eventually(
      () => relay.openClients.any(
        (client) => client.subscriptions.containsKey(keepingOn.id),
      ),
    );
  });
}
