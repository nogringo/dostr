import 'dart:async';

import 'package:dostr_core/src/domain_layer/entities/relay_connection_key.dart';
import 'package:dostr_core/src/domain_layer/entities/relay_failure.dart';
import 'package:dostr_core/src/domain_layer/entities/relay_protocol_handler.dart';
import 'package:dostr_core/src/domain_layer/entities/relay_publish_outcome.dart';
import 'package:dostr_core/src/domain_layer/repositories/nostr_transport.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/publish_state.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/relay_connection.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/relay_manager.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/relay_manager_parts.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/relay_manager_protocol.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/request_state.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

class _NeedsConnection extends RelayProtocolHandler {
  final RelayConnectionKey key;

  _NeedsConnection(this.key);

  @override
  bool hasWorkOn(RelayConnectionKey key) => key == this.key;
}

class _Transport implements NostrTransport {
  bool closed = false;
  void Function()? onClose;
  final controller = StreamController<dynamic>();

  @override
  Future<void> ready = Future.value();
  @override
  bool get isOpen => !closed;
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
  int? get closeCode => null;
  @override
  String? get closeReason => null;
}

class _NoConnections {
  NostrTransport call(String url) =>
      throw StateError('Tests must not open network connections');
}

class _Signer implements NostrSigner {
  @override
  bool get canSign => true;
  @override
  String get publicKey => 'a' * 64;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late RelayManagerParts parts;
  late RelayManager manager;
  final requests = <RequestState>[];
  final publishes = <PublishState>[];
  final anonymous = RelayConnectionKey.anonymous(
    RelayUrl.parse('wss://relay.example'),
  );
  final authenticated = RelayConnectionKey.authenticated(
    RelayUrl.parse('wss://relay.example'),
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  final other = RelayConnectionKey.anonymous(
    RelayUrl.parse('wss://other.example'),
  );

  _Transport connect(RelayConnectionKey key) {
    final transport = _Transport();
    parts.connections.relays[key] = RelayConnection(
      key,
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
    final request = RequestState(id, closeOnEose: query);
    request.received.listen((_) {});
    if (key != null) request.addRequest(key, filters);
    parts.requests.inFlight[id] = request;
    requests.add(request);
    return request;
  }

  PublishState publish(String id, {required RelayUrl url}) {
    final publish = PublishState(
      Nip01Event(pubkey: 'a' * 64, kind: 1, tags: [], content: id),
      relays: [url],
      timeout: const Duration(minutes: 1),
    );
    parts.publishes.inFlight[id] = [publish];
    publishes.add(publish);
    return publish;
  }

  setUp(() {
    manager = RelayManager(nostrTransportFactory: _NoConnections().call);
    parts = relayManagerParts(manager);
  });

  tearDown(() async {
    for (final request in requests) {
      await request.close();
    }
    requests.clear();
    for (final publish in publishes) {
      for (final url in publish.relays.keys) {
        publish.end(url, const RelayPublishOutcome.accepted());
      }
      await publish.done;
    }
    publishes.clear();
    await manager.dispose();
  });

  test('idle anonymous and authenticated transports are removed', () async {
    final anonTransport = connect(anonymous);
    final authTransport = connect(authenticated);
    await manager.closeIdleConnections();
    expect(parts.connections.relays, isEmpty);
    expect(anonTransport.closed, isTrue);
    expect(authTransport.closed, isTrue);
  });

  test('live subscription retains exact key after EOSE', () async {
    final anonTransport = connect(anonymous);
    final authTransport = connect(authenticated);
    final subscription = request('subscription', key: authenticated);
    subscription.requests[authenticated]!.markCaughtUp();
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
      subscription.requests[authenticated]!.markRetryingAuth();
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
    done.requests[authenticated]!.markCaughtUp();
    await manager.closeIdleConnections();
    expect(parts.connections.relays.keys, [anonymous]);
  });

  test('a publish keeps only the connection it goes out on', () async {
    connect(anonymous);
    final bound = connect(authenticated);
    final unrelated = connect(other);
    publish('event', url: anonymous.url);
    await manager.closeIdleConnections();
    expect(parts.connections.relays.keys, [anonymous]);
    expect(bound.closed, isTrue);
    expect(unrelated.closed, isTrue);
  });

  test(
    'a publish moving to a bound connection frees the anonymous one',
    () async {
      connect(anonymous);
      connect(authenticated);
      publish('event', url: anonymous.url).relays[anonymous.url]!
        ..key = authenticated
        ..progress = RelayPublishProgress.retryingAuth;
      await manager.closeIdleConnections();
      expect(parts.connections.relays.keys, [authenticated]);
    },
  );

  test('a request that has not picked a relay keeps nothing open', () async {
    connect(anonymous);
    connect(other);
    request('discovering').beginPendingConnection();
    await manager.closeIdleConnections();
    expect(parts.connections.relays, isEmpty);
  });

  test('a request still picking relays keeps only those it picked', () async {
    connect(anonymous);
    final idle = connect(other);
    request('selecting', key: anonymous).beginPendingConnection();
    await manager.closeIdleConnections();
    expect(idle.closed, isTrue);
    expect(parts.connections.relays.keys, [anonymous]);
  });

  test('a connection whose socket is being opened is retained', () async {
    connect(anonymous);
    connect(other);
    final opening = Completer<RelayFailure?>();
    parts.connections.relays[anonymous]!.opening = opening.future;
    await manager.closeIdleConnections();
    expect(parts.connections.relays.keys, [anonymous]);
    opening.complete();
  });

  test(
    'authentication waiting for challenge keeps its bound connection',
    () async {
      connect(anonymous);
      connect(authenticated);
      await manager.openConnectionAs(anonymous.url, _Signer());
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
