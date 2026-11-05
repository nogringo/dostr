import 'dart:async';
import 'dart:collection';

import '../../config/relay_defaults.dart';
import '../../config/request_defaults.dart';
import '../../shared/logger/logger.dart';
import '../../src/nostr_message_raw.dart';
import '../../src/relay_auth.dart';
import '../../src/relay_broadcasts.dart';
import '../../src/relay_connections.dart';
import '../../src/relay_manager_parts.dart';
import '../../src/relay_requests.dart';
import '../entities/account.dart';
import '../entities/auth_handler.dart';
import '../entities/auth_policy.dart';
import '../entities/relay_connection_key.dart';
import '../entities/relay_connectivity.dart';
import '../entities/relay_protocol_handler.dart';
import '../repositories/auth_accounts.dart';
import '../repositories/nostr_transport.dart';

export 'relay_reqs/relay_publish.dart' show RelayPublish, RelayPublishes;
export 'relay_reqs/relay_reqs.dart' show RelayReq, RelayReqs;

///  relay manager, responsible for lifecycle of relays, sending messages, \
///  and help with tracking of requests
class RelayManager {
  final Completer<void> _seedRelaysCompleter = Completer<void>();

  /// completes when all seed relays are connected
  Future<void> get seedRelaysConnected => _seedRelaysCompleter.future;

  late final RelayAuth _auth;
  late final RelayConnections _connections;
  late final RelayRequests _requests;
  late final RelayBroadcasts _broadcasts;

  final List<RelayProtocolHandler> _protocolHandlers = [];

  /// Are reconnects allowed when a connection drops?
  bool get allowReconnectRelays => _connections.allowReconnect;
  set allowReconnectRelays(bool allow) => _connections.allowReconnect = allow;

  /// stream of connection updates, used to notify connectivity changes, latest
  /// value is cached. A relay can hold several connections, so this cannot be
  /// indexed by url; group by [RelayConnectivity.url] if you need to.
  Stream<List<RelayConnectivity>> get relayConnectivityChanges =>
      _connections.changes;

  /// Every connection this manager holds, connected or not, by key.
  Map<RelayConnectionKey, RelayConnectivity> get connectivities =>
      UnmodifiableMapView(_connections.relays);

  /// Clean urls of the relays this manager does not connect to.
  Set<String> get blockedRelays => _connections.blockedRelays;

  /// Whether a broadcast of [eventId] is still waiting on its relays.
  bool isBroadcasting(String eventId) => _broadcasts.isBroadcasting(eventId);

  /// Creates a new relay manager.
  ///
  /// [nostrTransportFactory] opens the sockets, usually websockets.
  /// [authCallbackTimeout] is how long an AUTH waits for its OK, and
  /// [authChallengeTimeout] how long a NIP-42 challenge is waited for once
  /// authentication was asked for. [authHandler] is asked before a connection
  /// bound to an identity is opened.
  RelayManager({
    required NostrTransportFactory nostrTransportFactory,
    AuthAccounts? accounts,
    List<String> bootstrapRelays = const [],
    bool allowReconnect = true,
    Duration authCallbackTimeout =
        RequestDefaults.DEFAULT_AUTH_CALLBACK_TIMEOUT,
    Duration authChallengeTimeout =
        RequestDefaults.DEFAULT_AUTH_CHALLENGE_TIMEOUT,
    AuthHandler? authHandler,
  }) {
    _auth = RelayAuth(
      accounts: accounts,
      authHandler: authHandler,
      okTimeout: authCallbackTimeout,
      challengeTimeout: authChallengeTimeout,
    );
    _connections = RelayConnections(
      nostrTransportFactory: nostrTransportFactory,
      auth: _auth,
      onMessage: _dispatch,
      allowReconnect: allowReconnect,
    );
    _requests = RelayRequests(connections: _connections, auth: _auth);
    _broadcasts = RelayBroadcasts(connections: _connections, auth: _auth);
    _connections.listener = _requests;
    bindRelayManagerParts(
      this,
      RelayManagerParts(
        auth: _auth,
        connections: _connections,
        requests: _requests,
        broadcasts: _broadcasts,
      ),
    );
    _connectSeedRelays(bootstrapRelays);
  }

  /// Hands [handler] the messages, CLOSED and NOTICE this manager does not
  /// handle itself, and keeps the connections it still needs open.
  void addProtocolHandler(RelayProtocolHandler handler) {
    _protocolHandlers.add(handler);
  }

  /// Stops handing messages to [handler].
  void removeProtocolHandler(RelayProtocolHandler handler) {
    _protocolHandlers.remove(handler);
  }

  /// Connects to the bootstrap relays, if any.
  Future<void> _connectSeedRelays(Iterable<String> urls) async {
    await Future.wait(
      urls.map((url) => connectRelay(dirtyUrl: url)).toList(),
    ).whenComplete(() {
      if (!_seedRelaysCompleter.isCompleted) {
        _seedRelaysCompleter.complete();
      }
    });
  }

  /// Every open connection, anonymous or bound, so a relay can show up more
  /// than once. [isRelayConnected] checks a single relay.
  List<RelayConnectivity> get connectedRelays => _connections.connectedRelays;

  /// Connected connections bound to nobody, one per relay at most.
  ///
  /// Engines pick relays, not identities: sending on every connection of a
  /// relay would duplicate the request, and sending on a bound one would make
  /// it attributable. An identity is added later, by the re-route, and only on
  /// the relays that ask for one.
  List<RelayConnectivity> get connectedAnonymousRelays =>
      _connections.connectedAnonymousRelays;

  /// Whether the anonymous connection to [url] is open.
  bool isRelayConnected(String url) => _connections.isRelayConnected(url);

  /// checks if the connection identified by [key] is open
  bool isConnectionOpen(RelayConnectionKey key) =>
      _connections.isConnectionOpen(key);

  /// Opens the anonymous connection to a relay. Returns whether it is
  /// connected, and the error message if it is not. A connection bound to an
  /// identity is opened with [openConnectionAs].
  Future<({bool connected, String? error})> connectRelay({
    required String dirtyUrl,
    Duration connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
  }) => _connections.connectRelay(
    dirtyUrl: dirtyUrl,
    connectTimeout: connectTimeout,
  );

  /// Reconnects the anonymous connection to a relay, if it is closed.
  Future<bool> reconnectRelay(String url, {bool force = false}) =>
      _connections.reconnectRelay(url, force: force);

  /// Reconnects the connection identified by [key], if it is closed. An
  /// authenticated connection comes back authenticated or not at all.
  ///
  /// [as] is the identity to open a bound connection as, for a caller that has
  /// it in hand. Without it the account is looked up, which only works for a
  /// registered one.
  Future<bool> reconnectConnection(
    RelayConnectionKey key, {
    bool force = false,
    Account? as,
    TimeoutPausable? pausing,
  }) => _connections.reconnectConnection(
    key,
    force: force,
    as: as,
    pausing: pausing,
  );

  /// Closes and clears only transport-scoped state of every connection to
  /// [url], anonymous or bound, while keeping the entries and relay-scoped
  /// metadata in memory.
  Future<void> resetConnectionsTo(String url) async {
    await Future.wait(
      _connections.keysFor(url).map(_connections.resetConnection),
    );
  }

  /// Reconnects every connection that is not connected, even one that just
  /// failed to, and replays the requests it was carrying. Call this when the
  /// app learns that the network is back.
  Future<void> reconnectClosedConnections() =>
      _connections.reconnectClosedConnections();

  /// Waits until a REQ with [id] is sent on a connected relay.
  Future<void> waitForRequestSent(String id, Duration timeout) =>
      _connections.waitForRequestSent(id, timeout);

  /// Sends [message], a JSON array such as `["NEG-CLOSE", subscriptionId]`, on
  /// the connection behind [key] once its socket is ready. It is dropped, and
  /// logged, when there is no such connection or its socket goes away first.
  void send(RelayConnectionKey key, List<dynamic> message) =>
      _connections.send(key, message);

  /// Opens the connection towards [url] bound to [account]. The binding says
  /// which identity this socket may ever assume, not that it is already
  /// authenticated: relays are free to send their challenge whenever they want,
  /// and some only send it once a request needs it.
  ///
  /// A new binding is first put to the [AuthHandler], with [pausing] paused
  /// while it decides. A connection that already exists was agreed to when it
  /// was first opened, so reconnecting it does not ask again.
  Future<RelayConnectivity?> openConnectionAs(
    String url,
    Account account, {
    Duration connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
    TimeoutPausable? pausing,
  }) => _connections.openConnectionAs(
    url,
    account,
    connectTimeout: connectTimeout,
    pausing: pausing,
  );

  /// Answers the challenge for [key] and completes once the relay accepted the
  /// AUTH event. Concurrent callers share a single AUTH.
  Future<bool> authenticateConnection(RelayConnectionKey key) =>
      _connections.authenticate(key);

  /// Account [auth] authenticates as, null when it must stay unattributable.
  Account? accountForAuth(AuthPolicy? auth) => _auth.accountForAuth(auth);

  /// Routes a message from [relayConnectivity] to whatever it answers.
  Future<void> _dispatch(
    NostrMessageRaw nostrMsg,
    RelayConnectivity relayConnectivity,
    dynamic message,
  ) {
    final key = relayConnectivity.key;
    switch (nostrMsg.type) {
      case NostrMessageRawType.unknown:
        final data = nostrMsg.otherData;
        if (data is List &&
            List.of(
              _protocolHandlers,
            ).any((handler) => handler.onMessage(key, data))) {
          break;
        }
        Logger.log.w(
          () =>
              "Received unhandled message from ${relayConnectivity.url}: ${nostrMsg.otherData}",
        );
      case NostrMessageRawType.invalid:
        Logger.log.w(
          () =>
              "Received invalid message from ${relayConnectivity.url}: ${nostrMsg.otherData}",
        );
      case NostrMessageRawType.ok:
        final eventJson = nostrMsg.otherData;
        final String eventId = eventJson[1];
        final bool success = eventJson[2];
        final msg = _stringAt(eventJson, 3);

        // an AUTH is only answered by the connection it was sent on
        final session = _auth.existingSessionOf(key);
        if (session != null && session.receiveOk(eventId, success)) {
          if (success) {
            Logger.log.d(() => "AUTH OK for $eventId");
          } else {
            Logger.log.e(() => "AUTH failed for $eventId: $msg");
          }
          break;
        }

        //nip 20 used to notify clients if an EVENT was successful
        if (!success) {
          Logger.log.e(
            () => "NOT OK from ${relayConnectivity.url}: $eventJson",
          );
        }
        _broadcasts.routeOk(eventId, relayConnectivity, success, msg ?? '');
      case NostrMessageRawType.notice:
        final eventJson = nostrMsg.otherData;
        final String noticeMsg = eventJson[1];
        Logger.log.w(() => "NOTICE from ${relayConnectivity.url}: $noticeMsg");
        _requests.logActive();
        for (final handler in List.of(_protocolHandlers)) {
          handler.onNotice(key, noticeMsg);
        }
      case NostrMessageRawType.event:
        _requests.handleEvent(
          nostrMsg,
          relayConnectivity,
          message.toString().codeUnits.length,
        );
      case NostrMessageRawType.eose:
        final eventJson = nostrMsg.otherData;
        Logger.log.d(
          () => "EOSE from ${relayConnectivity.url}: ${eventJson[1]}",
        );
        _requests.handleEose(eventJson, relayConnectivity);
      case NostrMessageRawType.closed:
        final eventJson = nostrMsg.otherData;
        final String id = eventJson[1];
        final closedMsg = _stringAt(eventJson, 2);
        Logger.log.w(
          () =>
              " CLOSED subscription url: ${relayConnectivity.url} id: $id msg: ${closedMsg ?? ''}",
        );
        // a protocol session is not a REQ: it owns its own retry and never has
        // a RequestState for the auth-required branch to find
        for (final handler in List.of(_protocolHandlers)) {
          if (handler.onClosed(key, id, closedMsg)) return Future.value();
        }
        _requests.handleClosed(id, closedMsg, relayConnectivity);
      case NostrMessageRawType.auth:
        final eventJson = nostrMsg.otherData;
        // nip 42 used to send authentication challenges
        final challenge = eventJson[1];
        Logger.log.d(() => "AUTH challenge from $key: $challenge");

        _auth.sessionOf(key).receiveChallenge(challenge);

        // an anonymous connection never answers a challenge: signing here would
        // bind it to an identity nobody asked for, and every request already on
        // it would become attributable. A bound one answers as soon as it can.
        if (!key.isAnonymous) {
          unawaited(_connections.authenticate(key));
        }
    }
    return Future.value();
  }

  static String? _stringAt(List<dynamic> message, int index) =>
      index < message.length && message[index] is String
      ? message[index]
      : null;

  /// Closes every connection to [url], anonymous or bound, and forgets them.
  Future<void> closeConnectionsTo(String url) async {
    await Future.wait(_connections.keysFor(url).map(closeConnection));
  }

  /// Closes connections that no longer carry any tracked network work.
  ///
  /// Call this after optional subscriptions stop, for example when an app goes
  /// into the background. This is not an eviction timer: a live subscription
  /// keeps its connection even after EOSE, and authentication/reconnect work
  /// keeps the exact connection it is preparing to use.
  ///
  /// Request discovery does not yet identify every target connection. Defer
  /// pruning while such work is in progress instead of guessing its targets.
  /// Broadcasts track relay URLs rather than identities, so both anonymous and
  /// authenticated connections at an in-flight broadcast's URL are retained.
  Future<void> closeIdleConnections() async {
    var changed = false;
    try {
      for (final key in _connections.relays.keys.toList()) {
        // Re-evaluate after each asynchronous close. Another operation may
        // have claimed the next connection while the previous one was closing.
        if (_requests.hasUnassignedWork || _broadcasts.hasUnassignedWork) {
          break;
        }
        if (_connectionHasWork(key)) continue;
        await closeConnection(key);
        changed = true;
      }
    } finally {
      if (changed) _connections.notifyChanged();
    }
  }

  bool _connectionHasWork(RelayConnectionKey key) =>
      !_connections.relays.containsKey(key) ||
      _connections.isOpening(key) ||
      _auth.isAuthenticating(key) ||
      _requests.hasWorkOn(key) ||
      _broadcasts.hasWorkOn(key) ||
      _protocolHandlers.any((handler) => handler.hasWorkOn(key));

  /// Closes one connection and forgets it. An entry that lost its transport, to
  /// a reset or to a failed connection attempt, is forgotten just the same:
  /// leaving it behind keeps its auth state alive and makes it reconnect. The
  /// REQs still open on it end there as `RelayRequestStatus.disconnected`.
  Future<void> closeConnection(RelayConnectionKey key) =>
      _connections.closeConnection(key);

  /// Closes all transports
  Future<void> closeAllTransports() => _connections.closeAll();

  /// The anonymous connection to [url], if there is one.
  RelayConnectivity? getRelayConnectivity(String url) =>
      _connections.getRelayConnectivity(url);

  /// return [RelayConnectivity] of one connection, anonymous or bound
  RelayConnectivity? getConnectivity(RelayConnectionKey key) =>
      _connections.relays[key];
}
