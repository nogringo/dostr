import 'dart:async';

import 'package:test/test.dart';
import 'package:ndk_core/domain_layer/entities/account.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_state.dart';
import 'package:ndk_core/src/broadcast_state.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_core/src/relay_manager_parts.dart';
import 'package:ndk_core/domain_layer/entities/relay.dart';
import 'package:ndk_core/domain_layer/entities/relay_connection_key.dart';
import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';
import 'package:ndk_core/domain_layer/entities/relay_protocol_handler.dart';
import 'package:ndk_core/src/request_state.dart';
import 'package:ndk_core/domain_layer/repositories/event_signer.dart';
import 'package:ndk_core/domain_layer/repositories/nostr_transport.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';

class _NeedsConnection extends RelayProtocolHandler {
  final RelayConnectionKey key;

  _NeedsConnection(this.key);

  @override
  bool hasWorkOn(RelayConnectionKey key) => key == this.key;
}

class _Transport implements NostrTransport {
  bool closed = false;
  bool connecting = false;
  void Function()? onClose;
  final controller = StreamController<dynamic>();

  @override
  Future<void> ready = Future.value();
  @override
  bool isOpen() => !closed;
  @override
  bool isConnecting() => connecting;
  @override
  Future<void> close() async {
    closed = true;
    onClose?.call();
  }

  @override
  void send(dynamic data) {}
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) => controller.stream.listen(onData, onError: onError, onDone: onDone);
  @override
  int? closeCode() => null;
  @override
  String? closeReason() => null;
}

class _NoConnections implements NostrTransportFactory {
  @override
  NostrTransport call(
    String url, {
    Function? onReconnect,
    Function(int?, Object?, String?)? onDisconnect,
  }) => throw StateError('Tests must not open network connections');
}

class _Signer implements EventSigner {
  @override
  bool canSign() => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late RelayManagerParts parts;
  late RelayManager manager;
  final requests = <RequestState>[];
  final broadcasts = <BroadcastState>[];
  final anonymous = RelayConnectionKey.anonymous('wss://relay.example');
  final authenticated = RelayConnectionKey.authenticated(
    'wss://relay.example',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  final other = RelayConnectionKey.anonymous('wss://other.example');

  _Transport connect(RelayConnectionKey key) {
    final transport = _Transport();
    parts.connections.relays[key] = RelayConnectivity(
      key: key,
      relay: Relay(url: key.url),
      relayTransport: transport,
    );
    return transport;
  }

  RequestState request(
    String id, {
    RelayConnectionKey? key,
    bool query = false,
  }) {
    final filters = [
      Filter(kinds: [1]),
    ];
    final request = query
        ? RequestState.query(id)
        : RequestState.subscription(id);
    request.networkController.stream.listen((_) {});
    if (key != null) request.addRequest(key, filters);
    parts.requests.inFlight[id] = request;
    requests.add(request);
    return request;
  }

  BroadcastState broadcast(String id, {String? url}) {
    final broadcast = BroadcastState(timeout: const Duration(minutes: 1));
    parts.broadcasts.inFlight[id] = [broadcast];
    broadcasts.add(broadcast);
    if (url != null) {
      broadcast.broadcasts[url] = RelayBroadcastResponse(relayUrl: url);
    }
    return broadcast;
  }

  setUp(() {
    manager = RelayManager(
      nostrTransportFactory: _NoConnections(),
      bootstrapRelays: [],
    );
    parts = relayManagerParts(manager);
  });

  tearDown(() async {
    for (final request in requests) {
      await request.close();
    }
    requests.clear();
    for (final broadcast in broadcasts) {
      if (broadcast.broadcasts.isEmpty) {
        broadcast.closeIfNoRelays();
      } else if (!broadcast.networkController.isClosed) {
        for (final url in broadcast.broadcasts.keys.toList()) {
          broadcast.networkController.add(
            RelayBroadcastResponse(
              relayUrl: url,
              okReceived: true,
              broadcastSuccessful: true,
            ),
          );
        }
      }
      await broadcast.publishDoneFuture;
    }
    broadcasts.clear();
    await manager.closeAllTransports();
  });

  test('idle anonymous and authenticated transports are removed', () async {
    final anonTransport = connect(anonymous);
    final authTransport = connect(authenticated);
    await manager.closeIdleConnections();
    expect(parts.connections.relays, isEmpty);
    expect(anonTransport.closed, isTrue);
    expect(authTransport.closed, isTrue);
  });

  test(
    'request-sent waiter completes on exact REQ and supports late waiters',
    () async {
      connect(anonymous);
      final pending = manager.waitForRequestSent(
        'wanted',
        const Duration(seconds: 1),
      );
      final notes = Filter(kinds: [1]).toMap();
      manager.send(anonymous, ['REQ', 'other', notes]);
      manager.send(anonymous, ['REQ', 'wanted', notes]);
      await pending;
      await manager.waitForRequestSent('wanted', const Duration(seconds: 1));
      await expectLater(
        manager.waitForRequestSent('missing', const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('live subscription retains exact key after EOSE', () async {
    final anonTransport = connect(anonymous);
    final authTransport = connect(authenticated);
    final subscription = request('subscription', key: authenticated);
    subscription.requests[authenticated]!.receivedEOSE = true;
    await manager.closeIdleConnections();
    expect(anonTransport.closed, isTrue);
    expect(authTransport.closed, isFalse);
    expect(parts.connections.relays.keys, [authenticated]);
  });

  test('both identities stay when separate subscriptions own them', () async {
    connect(anonymous);
    connect(authenticated);
    request('anonymous', key: anonymous);
    request('authenticated', key: authenticated);
    await manager.closeIdleConnections();
    expect(
      parts.connections.relays.keys,
      unorderedEquals([anonymous, authenticated]),
    );
  });

  test(
    'closed request frees connection but auth retry keeps its key',
    () async {
      final anonTransport = connect(anonymous);
      final authTransport = connect(authenticated);
      final subscription = request('subscription', key: anonymous);
      subscription.requests[anonymous]!.markClosed('auth-required');
      subscription.addRequest(authenticated, [
        Filter(kinds: [1]),
      ]);
      subscription.requests[authenticated]!.markClosed('auth-required');
      subscription.requests[authenticated]!.retryingAuth = true;
      await manager.closeIdleConnections();
      expect(anonTransport.closed, isTrue);
      expect(authTransport.closed, isFalse);
    },
  );

  test('unfinished query stays; EOSE query frees its connection', () async {
    connect(anonymous);
    connect(authenticated);
    request('pending-query', key: anonymous, query: true);
    final done = request('done-query', key: authenticated, query: true);
    done.requests[authenticated]!.receivedEOSE = true;
    await manager.closeIdleConnections();
    expect(parts.connections.relays.keys, [anonymous]);
  });

  test(
    'broadcast conservatively keeps both identities at target URL',
    () async {
      connect(anonymous);
      connect(authenticated);
      final unrelated = connect(other);
      broadcast('event', url: anonymous.url);
      await manager.closeIdleConnections();
      expect(
        parts.connections.relays.keys,
        unorderedEquals([anonymous, authenticated]),
      );
      expect(unrelated.closed, isTrue);
    },
  );

  test(
    'unassigned request discovery defers pruning until keys are known',
    () async {
      connect(anonymous);
      final idle = connect(other);
      final pending = request('discovering');
      await manager.closeIdleConnections();
      expect(idle.closed, isFalse);
      pending.addRequest(anonymous, [
        Filter(kinds: [1]),
      ]);
      await manager.closeIdleConnections();
      expect(idle.closed, isTrue);
      expect(parts.connections.relays.keys, [anonymous]);
    },
  );

  test(
    'pending connection selection defers pruning even with other known keys',
    () async {
      connect(anonymous);
      final idle = connect(other);
      final pending = request('selecting', key: anonymous);
      pending.pendingConnections = 1;
      await manager.closeIdleConnections();
      expect(idle.closed, isFalse);
      pending.pendingConnections = 0;
      await manager.closeIdleConnections();
      expect(idle.closed, isTrue);
    },
  );

  test('unassigned broadcast discovery defers pruning', () async {
    connect(anonymous);
    final idle = connect(other);
    final pending = broadcast('discovering');
    await manager.closeIdleConnections();
    expect(idle.closed, isFalse);
    pending.broadcasts[anonymous.url] = RelayBroadcastResponse(
      relayUrl: anonymous.url,
    );
    await manager.closeIdleConnections();
    expect(idle.closed, isTrue);
  });

  test('ongoing transport and relay connection setup are retained', () async {
    connect(anonymous).connecting = true;
    connect(authenticated);
    parts.connections.relays[authenticated]!.relay.connecting = true;
    await manager.closeIdleConnections();
    expect(
      parts.connections.relays.keys,
      unorderedEquals([anonymous, authenticated]),
    );
  });

  test(
    'authentication waiting for challenge keeps its bound connection',
    () async {
      connect(anonymous);
      connect(authenticated);
      await manager.openConnectionAs(
        anonymous.url,
        Account(
          type: AccountType.privateKey,
          pubkey:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          signer: _Signer(),
        ),
      );
      final attempt = manager.authenticateConnection(authenticated);
      await manager.closeIdleConnections();
      expect(parts.connections.relays.keys, [authenticated]);
      await manager.closeConnection(authenticated);
      expect(await attempt, isFalse);
    },
  );

  test('a protocol handler keeps only the connections it needs', () async {
    connect(anonymous);
    connect(authenticated);
    manager.addProtocolHandler(_NeedsConnection(authenticated));
    await manager.closeIdleConnections();
    expect(parts.connections.relays.keys, [authenticated]);
  });

  test('ownership is rechecked after each asynchronous close', () async {
    final first = connect(anonymous);
    connect(other);
    first.onClose = () => request('new-owner', key: other);
    await manager.closeIdleConnections();
    expect(parts.connections.relays.keys, [other]);
  });
}
