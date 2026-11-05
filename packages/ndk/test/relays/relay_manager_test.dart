// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'package:ndk/entities.dart';
import 'package:test/test.dart';

import '../mocks/mock_event_verifier.dart';
import '../mocks/mock_relay.dart';

void main() async {
  group('Relay Manager', () {
    final WebSocketClientNostrTransportFactory webSocketNostrTransportFactory =
        WebSocketClientNostrTransportFactory();

    test('Connect to relay', () async {
      MockRelay relay1 = MockRelay(name: "relay 1", explicitPort: 5044);
      await relay1.startServer();

      RelayManager manager = RelayManager(
        nostrTransportFactory: webSocketNostrTransportFactory,
      );
      await manager.connectRelay(dirtyUrl: relay1.url).then((value) {}).onError(
        (error, stackTrace) async {
          await relay1.stopServer();
        },
      );
      await relay1.stopServer();
    });

    test('every caller of a failed connect learns why it failed', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();

      RelayManager manager = RelayManager(
        nostrTransportFactory: webSocketNostrTransportFactory,
      );
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          manager.connectRelay(dirtyUrl: 'ws://127.0.0.1:$port'),
      ]);

      for (final result in results) {
        expect(result.connected, isFalse);
        expect(result.failure?.kind, RelayFailureKind.unreachable);
        expect(result.failure?.detail, contains('SocketException'));
      }
    });

    test('wasLastConnectTryLongerThanSeconds', () async {
      MockRelay relay1 = MockRelay(name: "relay 1", explicitPort: 5044);
      await relay1.startServer();

      RelayManager manager = RelayManager(
        nostrTransportFactory: webSocketNostrTransportFactory,
      );
      await manager.connectRelay(dirtyUrl: relay1.url).then((value) {}).onError(
        (error, stackTrace) async {
          await relay1.stopServer();
        },
      );

      expect(
        manager.connectivities[RelayConnectionKey.anonymous(relay1.url)]!.relay
            .wasLastConnectTryLongerThanSeconds(120),
        false,
      );
      await relay1.stopServer();
    });

    test('reconnects after relay-side socket close', () async {
      MockRelay relay1 = MockRelay(name: "relay 1", explicitPort: 5046);
      await relay1.startServer();

      RelayManager manager = RelayManager(
        nostrTransportFactory: webSocketNostrTransportFactory,
      );
      await manager.connectRelay(dirtyUrl: relay1.url);
      expect(manager.isRelayConnected(relay1.url), true);

      // The server registers the client asynchronously; closing before that
      // would close zero sockets and leave the client connected.
      final registrationDeadline = DateTime.now().add(Duration(seconds: 5));
      while (DateTime.now().isBefore(registrationDeadline) &&
          relay1.connectedClientCount == 0) {
        await Future.delayed(Duration(milliseconds: 10));
      }
      expect(relay1.connectedClientCount, 1);

      final relayConnectivity =
          manager.connectivities[RelayConnectionKey.anonymous(relay1.url)]!;
      expect(relayConnectivity.stats.connections, 1);

      // Relay-side disconnect: the server stays up, only the socket dies.
      await relay1.closeClientSockets();

      // A second successful connection can only come from the
      // reconnect-on-close path; the counter is monotonic, so this cannot
      // race with how fast the reconnect happens.
      final reconnectDeadline = DateTime.now().add(Duration(seconds: 5));
      while (DateTime.now().isBefore(reconnectDeadline) &&
          relayConnectivity.stats.connections < 2) {
        await Future.delayed(Duration(milliseconds: 50));
      }
      expect(
        relayConnectivity.stats.connections,
        greaterThanOrEqualTo(2),
        reason:
            'RelayManager should reconnect after the relay closed the socket.',
      );
      expect(manager.isRelayConnected(relay1.url), true);

      // Keep the teardown from racing another reconnect attempt against the
      // stopped server.
      manager.allowReconnectRelays = false;
      await manager.closeConnectionsTo(relay1.url);
      await relay1.stopServer();
    });

    test('Try to connect to dead relay', () async {
      RelayManager manager = RelayManager(
        nostrTransportFactory: webSocketNostrTransportFactory,
      );

      MockRelay relay1 = MockRelay(name: "relay 1");
      try {
        await manager.connectRelay(dirtyUrl: relay1.url);
        fail("should throw exception");
      } catch (e) {
        // success
      }
    });
    test('closing forgets a connection that lost its transport', () async {
      MockRelay relay1 = MockRelay(name: "relay 1");
      await relay1.startServer();

      RelayManager manager = RelayManager(
        nostrTransportFactory: webSocketNostrTransportFactory,
      );
      await manager.connectRelay(dirtyUrl: relay1.url);
      expect(manager.connectivities, isNotEmpty);

      await manager.resetConnectionsTo(relay1.url);
      await manager.closeAllTransports();

      expect(
        manager.connectivities,
        isEmpty,
        reason: "a connection without transport must not survive the close",
      );

      await relay1.stopServer();
    });

    test(
      'a CLOSED from one relay does not end the request on the others',
      () async {
        MockRelay relay1 = MockRelay(name: "relay 1", explicitPort: 5050);
        MockRelay relay2 = MockRelay(name: "relay 2", explicitPort: 5051);

        await relay1.startServer();
        await relay2.startServer();

        RelayManager manager = RelayManager(
          nostrTransportFactory: webSocketNostrTransportFactory,
        );
        await manager.connectRelay(dirtyUrl: relay1.url);
        await manager.connectRelay(dirtyUrl: relay2.url);

        final testFilters = [
          Filter(kinds: [1], limit: 10),
        ];
        final reqs = RelayReqs(
          relayManager: manager,
          eventVerifier: MockEventVerifier(),
        );
        final req = reqs.req(
          id: "test_request_123",
          relays: {relay1.url: testFilters, relay2.url: testFilters},
          closeOnEose: false,
          timeout: Duration(seconds: 30),
        );
        final List<Nip01Event> eventsReceived = [];
        req.events.listen((e) => eventsReceived.add(e.event));
        await Future.delayed(Duration(milliseconds: 100));

        relay1.sendClosed(req.id, message: "rate limited");
        await Future.delayed(Duration(milliseconds: 100));

        expect(req.outcomes[relay1.url]?.status, RelayRequestStatus.closed);
        expect(
          req.outcomes[relay2.url]?.status,
          isNot(RelayRequestStatus.closed),
        );
        expect(reqs.openIds, [
          req.id,
        ], reason: "relay2 still serves the request");

        final testEvent = Nip01Event(
          kind: 1,
          pubKey: "test_pubkey",
          content: "Test content from relay2",
          tags: [],
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        relay2.sendEvent(event: testEvent, subId: req.id);
        await Future.delayed(Duration(milliseconds: 100));

        expect(eventsReceived.map((e) => e.content), [
          "Test content from relay2",
        ], reason: "relay2 still delivers once relay1 sent CLOSED");

        await req.close();
        await relay1.stopServer();
        await relay2.stopServer();
      },
    );
  });
}
