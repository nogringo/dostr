import 'dart:async';

import 'package:ndk/entities.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../../mocks/mock_event_verifier.dart';

void main() async {
  group('connectivity test', () {
    late MockRelay relay0;
    late MockRelay relay1;
    late Ndk ndk;

    setUp(() async {
      relay0 = MockRelay(name: "relay 0", port: 5197);
      relay1 = MockRelay(name: "relay 1", port: 5198);

      await relay0.start();
      await relay1.start();

      final cache = MemCacheManager();
      final NdkConfig config = NdkConfig(
        eventVerifier: MockEventVerifier(),
        cache: cache,
        bootstrapRelays: [relay0.url],
        // logLevel: Logger.logLevels.trace,
        ignoreRelays: [],
      );

      ndk = Ndk(config);

      await ndk.bootstrapRelaysConnected;
    });

    tearDown(() async {
      await ndk.destroy();
      await relay0.stop();
      await relay1.stop();
    });

    test('state updates are received', () async {
      final completer = Completer<List<RelayConnectivity>>();

      bool isConnected(List<RelayConnectivity> connections, String url) =>
          connections.any(
            (connection) => connection.url == url && connection.isConnected,
          );

      final subscription = ndk.connectivity.relayConnectivityChanges.listen((
        event,
      ) {
        // When we detect a change where one relay is disconnected, complete the completer
        if (isConnected(event, relay0.url) && isConnected(event, relay1.url)) {
          completer.complete(event);
        }
      });

      ndk.requests.query(
        filters: [
          Filter(kinds: [1]),
        ],
        explicitRelays: [relay1.url],
      );

      // Wait for the disconnection event with a timeout
      final result = await completer.future.timeout(
        Duration(seconds: 10),
        onTimeout: () =>
            throw TimeoutException('Relay connection event not received'),
      );

      expect(isConnected(result, relay0.url), true);
      expect(isConnected(result, relay1.url), true);

      subscription.cancel();
    });

    test('try reconnect', () async {
      ndk.requests.query(
        filters: [
          Filter(kinds: [1]),
        ],
        explicitRelays: [relay1.url],
      );

      await _waitForRelayConnectionState(ndk, relay1.url, true);
      expect(
        ndk
            .relays
            .connectivities[RelayConnectionKey.anonymous(relay0.url)]
            ?.isConnected,
        true,
      );
      expect(
        ndk
            .relays
            .connectivities[RelayConnectionKey.anonymous(relay1.url)]
            ?.isConnected,
        true,
      );

      await ndk.relays.resetConnectionsTo(relay1.url);

      await _waitForRelayConnectionState(ndk, relay1.url, false);
      expect(
        ndk
            .relays
            .connectivities[RelayConnectionKey.anonymous(relay0.url)]
            ?.isConnected,
        true,
      );
      expect(
        ndk
            .relays
            .connectivities[RelayConnectionKey.anonymous(relay1.url)]
            ?.isConnected,
        false,
      );

      await ndk.connectivity.tryReconnect();
      await _waitForRelayConnectionState(ndk, relay1.url, true);
      expect(
        ndk
            .relays
            .connectivities[RelayConnectionKey.anonymous(relay0.url)]
            ?.isConnected,
        true,
      );
      expect(
        ndk
            .relays
            .connectivities[RelayConnectionKey.anonymous(relay1.url)]
            ?.isConnected,
        true,
      );
    });
  });
}

Future<void> _waitForRelayConnectionState(
  Ndk ndk,
  String relayUrl,
  bool expectedState,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));

  while (DateTime.now().isBefore(deadline)) {
    if (ndk
            .relays
            .connectivities[RelayConnectionKey.anonymous(relayUrl)]
            ?.isConnected ==
        expectedState) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  throw TimeoutException(
    'Relay $relayUrl did not reach expected connection state $expectedState',
  );
}
