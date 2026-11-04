import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_nostr_transport_factory.dart';
import 'package:ndk_core/domain_layer/repositories/nostr_transport.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import '../../../cashu/test/mocks/mock_event_verifier.dart';
import '../mocks/mock_relay.dart';

void main() {
  for (final engine in NdkEngine.values) {
    relayOutcomesTests(engine);
  }
  deadConnectionTests();
  notSentEndTests();
  fallbackTests();
}

/// What a response carries when it was built without a request behind it.
void fallbackTests() {
  group('relay outcomes fallback', () {
    test('a response built without outcomes reports empty ones', () async {
      final response = NdkResponse(
        "no-outcomes",
        const Stream<Nip01Event>.empty(),
      );

      expect(response.relayOutcomes, isEmpty);
      expect(await response.relayOutcomesDone, isEmpty);
      // the initial snapshot the stream promises, and then its end
      expect(await response.relayOutcomesStream.toList(), [
        <String, RelayRequestOutcome>{},
      ]);
    });
  });
}

/// Polls [condition] so a test does not depend on connect or reconnect timings.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String reason = 'condition never became true',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(reason);
}

/// A socket that dies for good, which only the plain transport can be made to
/// do: the reconnecting one keeps its message stream open across a drop.
void deadConnectionTests() {
  group('relay outcomes on a dead connection', () {
    test('a request nothing will send again reports disconnected', () async {
      final relay = MockRelay(
        name: "relay 1",
        signEvents: false,
        silenceRequests: true,
      );
      await relay.startServer();

      final manager = RelayManager(
        bootstrapRelays: [relay.url],
        nostrTransportFactory: WebSocketNostrTransportFactory(),
      );
      await manager.connectRelay(dirtyUrl: relay.url);

      final filter = Filter(kinds: [Nip01Event.kTextNodeKind]);
      final req =
          RelayReqs(
            relayManager: manager,
            eventVerifier: MockEventVerifier(),
          ).req(
            id: "dead-connection-test",
            relays: {
              relay.url: [filter],
            },
            // long enough that the timeout cannot be what ends the request
            timeout: Duration(seconds: 60),
          );
      await manager.waitForRequestSent(req.id, const Duration(seconds: 5));
      await _waitUntil(
        () => relay.connectedClientCount == 1,
        reason: 'the request never reached the relay',
      );

      // nothing will bring the socket back, so nothing owes the request a reply
      manager.allowReconnectRelays = false;
      await relay.closeClientSockets();

      await _waitUntil(
        () =>
            req.outcomes[relay.url]?.status == RelayRequestStatus.disconnected,
        reason: 'the request stayed on a socket nobody will reopen',
      );
      await req.done.timeout(const Duration(seconds: 5));

      await relay.stopServer();
    });
  });
}

/// A relay a request could not be sent to must neither hold the request open
/// nor end it while another relay still owes an answer.
void notSentEndTests() {
  group('relay outcomes of a request not sent everywhere', () {
    final key1 = Bip340.generatePrivateKey();
    final key2 = Bip340.generatePrivateKey();

    Nip01Event textNote(KeyPair key) => Bip340.signEvent(
      event: Nip01Event(
        kind: Nip01Event.kTextNodeKind,
        pubKey: key.publicKey,
        content: "some note from ${key.publicKey}",
        tags: [],
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
      privateKey: key.privateKey!,
    );

    Filter notesOf(KeyPair key) =>
        Filter(kinds: [Nip01Event.kTextNodeKind], authors: [key.publicKey]);

    RelayManager buildManager(
      List<String> seeds, {
      NostrTransportFactory? factory,
    }) => RelayManager(
      bootstrapRelays: seeds,
      // the transport Ndk uses: the plain one reports a socket open before its
      // handshake, so a relay nothing listens on would look reachable
      nostrTransportFactory: factory ?? WebSocketClientNostrTransportFactory(),
    );

    test(
      'a notSent relay with an open socket does not hold the request once the others are gone',
      () async {
        final notSent = MockRelay(name: "not sent", signEvents: false);
        final dropped = MockRelay(
          name: "dropped",
          signEvents: false,
          silenceRequests: true,
        );
        await notSent.startServer();
        await dropped.startServer();
        // the only transport whose socket can be made to die for good
        final manager = buildManager([
          notSent.url,
          dropped.url,
        ], factory: WebSocketNostrTransportFactory());
        addTearDown(() async {
          await manager.closeAllTransports();
          await notSent.stopServer();
          await dropped.stopServer();
        });
        await manager.seedRelaysConnected;

        final filter = notesOf(key1);
        final req =
            RelayReqs(
              relayManager: manager,
              eventVerifier: MockEventVerifier(),
            ).req(
              id: "open-socket-test",
              // long enough that the timeout cannot be what ends the request
              timeout: Duration(seconds: 60),
            );
        req.send(dropped.url, [filter]);
        await manager.waitForRequestSent(req.id, const Duration(seconds: 5));
        // a relay given up on while its socket stays open
        final notSentKey = RelayConnectionKey.anonymous(notSent.url);
        manager.blockedRelays.add(notSentKey.url);
        req.send(notSent.url, [filter]);
        req.seal();
        await _waitUntil(
          () => req.outcomes[notSent.url]?.status == RelayRequestStatus.notSent,
          reason: 'the blocked relay was sent the request',
        );

        manager.allowReconnectRelays = false;
        await dropped.closeClientSockets();

        await _waitUntil(
          () =>
              req.outcomes[dropped.url]?.status ==
              RelayRequestStatus.disconnected,
          reason: 'the dropped relay was never given up on',
        );
        expect(manager.isConnectionOpen(notSentKey), isTrue);
        await req.done.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              fail('no relay is left to answer, only the timeout would end it'),
        );
      },
    );

    test(
      'a relay still connecting is waited for, not reported notSent',
      () async {
        final connected = MockRelay(name: "connected", signEvents: false);
        final connecting = MockRelay(name: "connecting", signEvents: false);
        final connectedNote = textNote(key1);
        final connectingNote = textNote(key2);
        await connected.startServer(textNotes: {key1: connectedNote});
        await connecting.startServer(
          textNotes: {key2: connectingNote},
          delayConnection: Duration(seconds: 1),
        );
        final manager = buildManager([connected.url]);
        Future<void>? opening;
        addTearDown(() async {
          // MockRelay fails a handshake it still holds once its server stops
          await opening;
          await manager.closeAllTransports();
          await connected.stopServer();
          await connecting.stopServer();
        });
        await manager.seedRelaysConnected;

        // another request is already opening it
        opening = manager.connectRelay(dirtyUrl: connecting.url);
        final filter = Filter(
          kinds: [Nip01Event.kTextNodeKind],
          authors: [key1.publicKey, key2.publicKey],
        );
        final req =
            RelayReqs(
              relayManager: manager,
              eventVerifier: MockEventVerifier(),
            ).req(
              relays: {
                connected.url: [filter],
                connecting.url: [filter],
              },
            );
        final received = await req.events.toList();

        expect(req.outcomes, {
          connected.url: RelayRequestOutcome(RelayRequestStatus.eose),
          connecting.url: RelayRequestOutcome(RelayRequestStatus.eose),
        });
        expect(received.map((e) => e.id), contains(connectingNote.id));
      },
    );
  });
}

/// Both engines open their requests through the same RelayReqs, so both must
/// report the same outcomes.
void relayOutcomesTests(NdkEngine engine) {
  group('relay outcomes [${engine.name}]', () {
    final key1 = Bip340.generatePrivateKey();
    late MockRelay relay1;
    late Ndk ndk;

    Nip01Event textNote(KeyPair key) => Bip340.signEvent(
      event: Nip01Event(
        kind: Nip01Event.kTextNodeKind,
        pubKey: key.publicKey,
        content: "some note from key1",
        tags: [],
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
      privateKey: key.privateKey!,
    );

    Ndk buildNdk({AuthHandler? authHandler}) => Ndk(
      NdkConfig(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: engine,
        bootstrapRelays: [relay1.url],
        authHandler: authHandler,
      ),
    );

    NdkResponse queryKey1({Duration? timeout}) => ndk.requests.query(
      filter: Filter(
        kinds: [Nip01Event.kTextNodeKind],
        authors: [key1.publicKey],
      ),
      cacheRead: false,
      timeout: timeout,
    );

    tearDown(() async {
      await ndk.destroy();
      await relay1.stopServer();
    });

    test('a relay that sends its EOSE reports eose', () async {
      relay1 = MockRelay(name: "relay 1", signEvents: false);
      await relay1.startServer(textNotes: {key1: textNote(key1)});
      ndk = buildNdk();

      final response = queryKey1();
      final events = await response.future;

      expect(events, hasLength(1));
      expect(response.relayOutcomes, {
        relay1.url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
      expect(await response.relayOutcomesDone, response.relayOutcomes);
    });

    test(
      'a request merged into an identical one reports its outcomes',
      () async {
        relay1 = MockRelay(name: "relay 1", signEvents: false);
        await relay1.startServer(textNotes: {key1: textNote(key1)});
        ndk = buildNdk();

        final filter = Filter(
          kinds: [Nip01Event.kTextNodeKind],
          authors: [key1.publicKey],
        );
        final first = ndk.requests.query(filter: filter);
        final duplicate = ndk.requests.query(filter: filter);

        await first.future;
        await duplicate.future;

        expect(duplicate.relayOutcomes, {
          relay1.url: RelayRequestOutcome(RelayRequestStatus.eose),
        });
      },
    );

    test('the stream ends on the request, on its final outcomes', () async {
      relay1 = MockRelay(name: "relay 1", signEvents: false);
      await relay1.startServer(textNotes: {key1: textNote(key1)});
      ndk = buildNdk();

      final response = queryKey1();
      final streamed = response.relayOutcomesStream.toList();
      await response.future;

      final outcomes = await streamed;
      expect(outcomes.last, {
        relay1.url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
      expect(outcomes.last, await response.relayOutcomesDone);
    });

    test('the stream still ends when it is asked for too late', () async {
      relay1 = MockRelay(name: "relay 1", signEvents: false);
      await relay1.startServer(textNotes: {key1: textNote(key1)});
      ndk = buildNdk();

      final response = queryKey1();
      await response.future;

      // nothing is left to close a subject created this late, and it stays a
      // broadcast stream, so a second listener is served just like the first
      final stream = response.relayOutcomesStream;
      final ended = {relay1.url: RelayRequestOutcome(RelayRequestStatus.eose)};
      expect((await stream.toList()).last, ended);
      expect((await stream.toList()).last, ended);
    });

    test(
      'a merged request streams the outcomes of the one serving it',
      () async {
        relay1 = MockRelay(name: "relay 1", signEvents: false);
        await relay1.startServer(textNotes: {key1: textNote(key1)});
        ndk = buildNdk();

        final filter = Filter(
          kinds: [Nip01Event.kTextNodeKind],
          authors: [key1.publicKey],
        );
        final first = ndk.requests.query(filter: filter);
        final duplicate = ndk.requests.query(filter: filter);
        final streamed = duplicate.relayOutcomesStream.toList();

        await first.future;
        await duplicate.future;

        expect((await streamed).last, {
          relay1.url: RelayRequestOutcome(RelayRequestStatus.eose),
        });
      },
    );

    test('a relay that closes the request reports closed and why', () async {
      relay1 = MockRelay(
        name: "relay 1",
        signEvents: false,
        closeRequestsMessage: "blocked: you are not whitelisted",
      );
      await relay1.startServer(textNotes: {key1: textNote(key1)});
      ndk = buildNdk();

      final response = queryKey1();
      await response.future;

      expect(response.relayOutcomes, {
        relay1.url: RelayRequestOutcome(
          RelayRequestStatus.closed,
          message: "blocked: you are not whitelisted",
        ),
      });
    });

    test('a relay that stays silent reports timedOut', () async {
      relay1 = MockRelay(
        name: "relay 1",
        signEvents: false,
        silenceRequests: true,
      );
      await relay1.startServer(textNotes: {key1: textNote(key1)});
      ndk = buildNdk();

      final response = queryKey1(timeout: Duration(seconds: 1));
      await response.future;

      expect(response.relayOutcomes, {
        relay1.url: RelayRequestOutcome(RelayRequestStatus.timedOut),
      });
    });

    test(
      'a relay no connection reaches reports notSent, and the others end the request',
      () async {
        relay1 = MockRelay(name: "relay 1", signEvents: false);
        await relay1.startServer(textNotes: {key1: textNote(key1)});
        // never started, so nothing listens on its port
        final unreachable = MockRelay(name: "unreachable", signEvents: false);
        ndk = buildNdk();

        var timedOut = false;
        final response = ndk.requests.query(
          filter: Filter(
            kinds: [Nip01Event.kTextNodeKind],
            authors: [key1.publicKey],
          ),
          explicitRelays: [relay1.url, unreachable.url],
          cacheRead: false,
          timeout: Duration(seconds: 30),
          timeoutCallback: () => timedOut = true,
        );
        final events = await response.future;

        expect(events, hasLength(1));
        expect(timedOut, isFalse);
        expect(await response.relayOutcomesDone, {
          relay1.url: RelayRequestOutcome(RelayRequestStatus.eose),
          unreachable.url: RelayRequestOutcome(
            RelayRequestStatus.notSent,
            message: "could not connect",
          ),
        });

        await unreachable.stopServer();
      },
    );

    test(
      'a request none of its relays can be sent to ends without its timeout',
      () async {
        relay1 = MockRelay(name: "relay 1", signEvents: false);
        await relay1.startServer(textNotes: {key1: textNote(key1)});
        final unreachable = MockRelay(name: "unreachable", signEvents: false);
        ndk = buildNdk();

        var timedOut = false;
        final response = ndk.requests.query(
          filter: Filter(
            kinds: [Nip01Event.kTextNodeKind],
            authors: [key1.publicKey],
          ),
          explicitRelays: [unreachable.url],
          cacheRead: false,
          timeout: Duration(seconds: 30),
          timeoutCallback: () => timedOut = true,
        );

        expect(await response.future, isEmpty);
        expect(timedOut, isFalse);
        expect(await response.relayOutcomesDone, {
          unreachable.url: RelayRequestOutcome(
            RelayRequestStatus.notSent,
            message: "could not connect",
          ),
        });

        await unreachable.stopServer();
      },
    );

    test(
      'a paginated query streams a relay while its page is running',
      () async {
        relay1 = MockRelay(name: "relay 1", signEvents: false);
        await relay1.startServer(
          textNotes: {key1: textNote(key1)},
          delayResponse: Duration(seconds: 1),
        );
        ndk = buildNdk();

        final response = ndk.requests.query(
          filter: Filter(
            kinds: [Nip01Event.kTextNodeKind],
            authors: [key1.publicKey],
          ),
          cacheRead: false,
          paginate: true,
        );
        final streamed = response.relayOutcomesStream.toList();
        await response.future;

        final outcomes = await streamed;
        expect(
          outcomes,
          anyElement(
            equals({
              relay1.url: RelayRequestOutcome(RelayRequestStatus.pending),
            }),
          ),
          reason: 'a page still running must show its relay as pending',
        );
        expect(outcomes.last, {
          relay1.url: RelayRequestOutcome(RelayRequestStatus.eose),
        });
      },
    );

    test('a subscription still waiting on a relay reports pending', () async {
      relay1 = MockRelay(
        name: "relay 1",
        signEvents: false,
        silenceRequests: true,
      );
      await relay1.startServer(textNotes: {key1: textNote(key1)});
      ndk = buildNdk();

      final response = ndk.requests.subscription(
        filter: Filter(
          kinds: [Nip01Event.kTextNodeKind],
          authors: [key1.publicKey],
        ),
        cacheRead: false,
      );
      await Future.delayed(Duration(seconds: 1));

      expect(response.relayOutcomes, {
        relay1.url: RelayRequestOutcome(RelayRequestStatus.pending),
      });

      await ndk.requests.closeSubscription(response.requestId);

      expect(await response.relayOutcomesDone, {
        relay1.url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test('a subscription streams its relays until it is closed', () async {
      relay1 = MockRelay(
        name: "relay 1",
        signEvents: false,
        silenceRequests: true,
      );
      await relay1.startServer(textNotes: {key1: textNote(key1)});
      ndk = buildNdk();

      final response = ndk.requests.subscription(
        filter: Filter(
          kinds: [Nip01Event.kTextNodeKind],
          authors: [key1.publicKey],
        ),
        cacheRead: false,
      );
      final streamed = response.relayOutcomesStream.toList();
      await Future.delayed(Duration(seconds: 1));

      await ndk.requests.closeSubscription(response.requestId);

      expect((await streamed).last, {
        relay1.url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test(
      'a relay asking for auth we cannot answer reports its refusal',
      () async {
        relay1 = MockRelay(
          name: "relay 1",
          signEvents: false,
          requireAuthForRequests: true,
        );
        await relay1.startServer(textNotes: {key1: textNote(key1)});
        ndk = buildNdk();

        final response = queryKey1(timeout: Duration(seconds: 5));
        await response.future;

        final outcome = response.relayOutcomes[relay1.url];
        expect(outcome?.status, RelayRequestStatus.closed);
        expect(outcome?.message, startsWith("auth-required"));
      },
    );

    test('the connections to one relay collapse into one outcome', () async {
      relay1 = MockRelay(
        name: "relay 1",
        signEvents: false,
        requireAuthForRequests: true,
      );
      await relay1.startServer(textNotes: {key1: textNote(key1)});
      ndk = buildNdk(authHandler: (_, _) async => true);

      ndk.accounts.loginPrivateKey(
        pubkey: key1.publicKey,
        privkey: key1.privateKey!,
      );

      final response = queryKey1(timeout: Duration(seconds: 5));
      final events = await response.future;

      // the anonymous attempt was closed with auth-required and handed over to
      // an authenticated connection, which is the one that answered
      expect(events, hasLength(1));
      expect(response.relayOutcomes, {
        relay1.url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });
  });
}
