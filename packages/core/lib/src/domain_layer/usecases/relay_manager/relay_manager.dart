import 'dart:async';
import 'dart:collection';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../config/relay_defaults.dart';
import '../../../config/request_defaults.dart';
import '../../../shared/logger.dart';
import '../../../shared/nips/nip01/nostr_message_raw.dart';
import '../../entities/message_length_limit.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_connectivity.dart';
import '../../entities/relay_failure.dart';
import '../../entities/relay_protocol_handler.dart';
import '../../entities/subscription_limit.dart';
import '../../entities/timeout_pausable.dart';
import '../../repositories/nostr_transport.dart';
import 'publishes_in_flight.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';
import 'relay_manager_parts.dart';
import 'relay_requests.dart';

export '../relay_reqs/relay_publish.dart' show RelayPublish, RelayPublishes;
export '../relay_reqs/relay_reqs.dart' show RelayReq, RelayReqs;

/// Opens, keeps and closes the relay connections, authenticates them (NIP-42),
/// and routes what each relay sends to the REQs and publishes waiting for it.
///
/// Keep one for the whole app, and open REQs and publishes on it with
/// [RelayReqs] and [RelayPublishes].
final class RelayManager {
  late final RelayAuth _auth;
  late final RelayConnections _connections;
  late final RelayRequests _requests;
  late final PublishesInFlight _publishes;

  final List<RelayProtocolHandler> _protocolHandlers = [];

  /// Every connection each time one is added, starts connecting, opens, closes
  /// or is forgotten, as it stood then, the latest list cached. A relay can
  /// hold several connections, so this cannot be indexed by url; group by the
  /// url of [RelayConnectivity.key] if you need to.
  Stream<List<RelayConnectivity>> get relayConnectivityChanges =>
      _connections.changes;

  /// Every connection this manager holds, connected or not, by key, as it
  /// stands now.
  Map<RelayConnectionKey, RelayConnectivity> get connectivities =>
      Map.unmodifiable({
        for (final MapEntry(:key, :value) in _connections.relays.entries)
          key: value.snapshot(),
      });

  /// The relays this manager does not connect to, see [blockRelay].
  Set<RelayUrl> get blockedRelays =>
      UnmodifiableSetView(_connections.blockedRelays);

  /// Stops connecting to [url], and closes the connections already there.
  Future<void> blockRelay(RelayUrl url) {
    _connections.blockedRelays.add(url);
    return closeConnectionsTo(url);
  }

  /// Lets requests and publishes connect to [url] again.
  void unblockRelay(RelayUrl url) => _connections.blockedRelays.remove(url);

  /// Creates a new relay manager.
  ///
  /// [nostrTransportFactory] opens the sockets, usually websockets.
  /// [authCallbackTimeout] is how long an AUTH waits for its OK, and
  /// [authChallengeTimeout] how long a NIP-42 challenge is waited for once
  /// authentication was asked for. [authHandler] is asked before a connection
  /// bound to an identity is opened.
  ///
  /// A connection that drops is retried right away, then after a wait that
  /// starts at 500 milliseconds and doubles each time, for an hour. The
  /// default [reconnectMaximumStep] of 4 caps that wait at 4 seconds. Its
  /// requests are replayed once it is back. A socket that drops again within
  /// 10 seconds of coming back is not retried right away: it goes on with that
  /// wait. A connection that carries nothing
  /// [closeIdleConnections] would keep, when it drops or before an attempt, is
  /// forgotten instead.
  ///
  /// A connection with nothing [closeIdleConnections] would keep it for, and
  /// no message sent or received, is closed after [anonymousIdleTimeout], or
  /// [authenticatedIdleTimeout] when it is bound to an identity: reopening that
  /// one means authenticating again. Null keeps such connections open.
  ///
  /// A connection keeps at most as many REQs open as [subscriptionLimit] says
  /// its relay accepts, asked each time its socket opens. The others wait for
  /// a slot, and subscriptions leave a quarter of them to queries, at least
  /// one when there are several. No answer within 2 seconds, or none at all,
  /// gives 20, a cautious default and a tenth of what strfry accepts: answer
  /// it from the NIP-11 document of the relay, as `dostr_nip11` fetches it.
  ///
  /// A message longer than [messageLengthLimit] says its relay reads, also
  /// asked each time a socket opens, is not sent: a REQ ends there as notSent,
  /// an EVENT fails, both with [RelayFailureKind.messageTooLong]. REQs and
  /// EVENTs wait for its answer. A relay that closes a socket with a 1009 reads
  /// less than the longest message written there: nothing that long is sent to
  /// it again, and [onMessageLengthLearned] gets the url of the relay and the
  /// most bytes it may still be sent. Keep them to answer [messageLengthLimit]
  /// after a restart, so the limit is not learned again.
  RelayManager({
    required NostrTransportFactory nostrTransportFactory,
    AuthAccounts? accounts,
    bool allowReconnect = true,
    int reconnectMaximumStep = defaultReconnectMaximumStep,
    Duration? anonymousIdleTimeout = defaultAnonymousIdleTimeout,
    Duration? authenticatedIdleTimeout = defaultAuthenticatedIdleTimeout,
    Duration authCallbackTimeout = defaultAuthCallbackTimeout,
    Duration authChallengeTimeout = defaultAuthChallengeTimeout,
    AuthHandler? authHandler,
    SubscriptionLimit? subscriptionLimit,
    MessageLengthLimit? messageLengthLimit,
    FutureOr<void> Function(RelayUrl url, int length)? onMessageLengthLearned,
  }) {
    if (reconnectMaximumStep <= 0) {
      throw ArgumentError.value(
        reconnectMaximumStep,
        'reconnectMaximumStep',
        'must be positive',
      );
    }
    for (final (name, timeout) in [
      ('anonymousIdleTimeout', anonymousIdleTimeout),
      ('authenticatedIdleTimeout', authenticatedIdleTimeout),
    ]) {
      if (timeout != null && timeout <= Duration.zero) {
        throw ArgumentError.value(timeout, name, 'must be positive');
      }
    }
    _auth = RelayAuth(
      accounts: accounts,
      authHandler: authHandler,
      okTimeout: authCallbackTimeout,
      challengeTimeout: authChallengeTimeout,
    );
    _connections = RelayConnections(
      nostrTransportFactory: nostrTransportFactory,
      auth: _auth,
      listener: _ConnectionWork(this),
      anonymousIdleTimeout: anonymousIdleTimeout,
      authenticatedIdleTimeout: authenticatedIdleTimeout,
      allowReconnect: allowReconnect,
      reconnectMaximumStep: reconnectMaximumStep,
      subscriptionLimit: subscriptionLimit,
      messageLengthLimit: messageLengthLimit,
      onMessageLengthLearned: onMessageLengthLearned,
    );
    _requests = RelayRequests(connections: _connections, auth: _auth);
    _publishes = PublishesInFlight(connections: _connections, auth: _auth);
    bindRelayManagerParts(
      this,
      RelayManagerParts(
        auth: _auth,
        connections: _connections,
        requests: _requests,
        publishes: _publishes,
      ),
    );
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

  /// Opens the anonymous connection to [url]. Returns whether it is
  /// connected, and why if it is not. A refused connection is tried
  /// again until [connectTimeout] runs out, and one that dropped is tried now
  /// instead of after its backoff. A connection bound to an identity is
  /// opened with [openConnectionAs]. Throws a [StateError] once disposed.
  Future<({bool connected, RelayFailure? failure})> connectRelay(
    RelayUrl url, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    _checkNotDisposed();
    final failure = await _connections.connectNow(
      RelayConnectionKey.anonymous(url),
      connectTimeout: connectTimeout,
    );
    return (connected: failure == null, failure: failure);
  }

  /// Reconnects every connection that is not connected, even one that just
  /// failed to, and replays the requests it was carrying. Call this when the
  /// app learns that the network is back.
  Future<void> reconnectClosedConnections() =>
      _connections.reconnectClosedConnections();

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
  /// was first opened, so reconnecting it does not ask again. Throws a
  /// [StateError] once disposed.
  Future<RelayConnectivity?> openConnectionAs(
    RelayUrl url,
    NostrSigner account, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
    TimeoutPausable? pausing,
  }) async {
    _checkNotDisposed();
    if (!account.canSign) {
      logger.warning(() => "Cannot bind a connection to ${account.publicKey}");
      return null;
    }
    final key = RelayConnectionKey.authenticated(url, account.publicKey);
    final failure = await _connections.connectNow(
      key,
      as: account,
      pausing: pausing,
      connectTimeout: connectTimeout,
    );
    if (failure != null) {
      logger.info(() => "Could not open $key: $failure");
      return null;
    }
    return _connections.relays[key]?.snapshot();
  }

  /// Answers the challenge for [key] and completes once the relay accepted the
  /// AUTH event. Concurrent callers share a single AUTH. False when the
  /// connection is not open.
  Future<bool> authenticateConnection(RelayConnectionKey key) =>
      _connections.isConnectionOpen(key)
      ? _connections.authenticate(key)
      : Future.value(false);

  /// Account [auth] authenticates as, null when it must stay unattributable.
  NostrSigner? accountForAuth(AuthPolicy? auth) => _auth.accountForAuth(auth);

  /// Routes a message from [connection] to whatever it answers.
  void _dispatch(NostrMessageRaw nostrMsg, RelayConnection connection) {
    final key = connection.key;
    switch (nostrMsg.type) {
      case NostrMessageRawType.unknown:
        final data = nostrMsg.otherData;
        if (data is List &&
            List.of(
              _protocolHandlers,
            ).any((handler) => handler.onMessage(key, data))) {
          break;
        }
        logger.warning(
          () =>
              "Received unhandled message from ${connection.url}: ${nostrMsg.otherData}",
        );
      case NostrMessageRawType.invalid:
        logger.warning(
          () =>
              "Received invalid message from ${connection.url}: ${nostrMsg.otherData}",
        );
      case NostrMessageRawType.ok:
        final eventJson = nostrMsg.otherData;
        final String eventId = eventJson[1];
        final bool success = eventJson[2];
        final msg = _stringAt(eventJson, 3);

        // an AUTH is only answered by the connection it was sent on
        final session = connection.authSession;
        if (session != null && session.receiveOk(eventId, success)) {
          if (success) {
            logger.fine(() => "AUTH accepted on $key");
          } else {
            logger.warning(() => "AUTH refused on $key: $msg");
          }
          break;
        }

        logger.fine(
          () => "OK $success from ${connection.url} for $eventId: ${msg ?? ''}",
        );
        _publishes.routeOk(eventId, connection, success, msg ?? '');
      case NostrMessageRawType.notice:
        final eventJson = nostrMsg.otherData;
        final String noticeMsg = eventJson[1];
        logger.info(() => "NOTICE from ${connection.url}: $noticeMsg");
        _requests.logActive();
        for (final handler in List.of(_protocolHandlers)) {
          handler.onNotice(key, noticeMsg);
        }
      case NostrMessageRawType.event:
        _requests.handleEvent(nostrMsg, connection);
      case NostrMessageRawType.eose:
        final eventJson = nostrMsg.otherData;
        logger.fine(() => "EOSE from ${connection.url}: ${eventJson[1]}");
        _requests.handleEose(eventJson, connection);
      case NostrMessageRawType.closed:
        final eventJson = nostrMsg.otherData;
        final String id = eventJson[1];
        final closedMsg = _stringAt(eventJson, 2);
        logger.fine(
          () => "CLOSED from ${connection.url} for $id: ${closedMsg ?? ''}",
        );
        // a protocol session is not a REQ: it owns its own retry and never has
        // a RequestState for the auth-required branch to find
        for (final handler in List.of(_protocolHandlers)) {
          if (handler.onClosed(key, id, closedMsg)) return;
        }
        _requests.handleClosed(id, closedMsg, connection);
      case NostrMessageRawType.auth:
        final eventJson = nostrMsg.otherData;
        final challenge = eventJson[1];
        logger.fine(() => "AUTH challenge from $key: $challenge");

        _auth.sessionOf(connection).receiveChallenge(challenge);

        // an anonymous connection never answers a challenge: signing here would
        // bind it to an identity nobody asked for, and every request already on
        // it would become attributable. A bound one answers as soon as it can.
        if (!key.isAnonymous) {
          unawaited(_connections.authenticate(key));
        }
    }
  }

  static String? _stringAt(List<dynamic> message, int index) =>
      index < message.length && message[index] is String
      ? message[index]
      : null;

  /// Closes every connection to [url], anonymous or bound, and forgets them.
  Future<void> closeConnectionsTo(RelayUrl url) async {
    await Future.wait(_connections.keysFor(url).map(closeConnection));
  }

  /// Closes connections that no longer carry any tracked network work.
  ///
  /// Call this after optional subscriptions stop, for example when an app goes
  /// into the background, to close them without waiting for the idle timeouts
  /// given to the constructor. A live subscription keeps its connection even
  /// after EOSE, and authentication/reconnect work keeps the exact connection
  /// it is preparing to use.
  Future<void> closeIdleConnections() async {
    for (final key in _connections.relays.keys.toList()) {
      // Re-evaluate after each asynchronous close. Another operation may
      // have claimed the next connection while the previous one was closing.
      if (_connectionHasWork(key)) continue;
      await closeConnection(key);
    }
  }

  bool _connectionHasWork(RelayConnectionKey key) {
    final connection = _connections.relays[key];
    return connection == null ||
        connection.opening != null ||
        connection.isAuthenticating ||
        _requests.hasWorkOn(key) ||
        _publishes.hasWorkOn(key) ||
        _protocolHandlers.any((handler) => handler.hasWorkOn(key));
  }

  /// Closes one connection and forgets it. An entry that lost its transport, to
  /// a reset or to a failed connection attempt, is forgotten just the same:
  /// leaving it behind keeps its auth state alive and makes it reconnect. The
  /// REQs still open on it end there as `RelayRequestStatus.disconnected`.
  Future<void> closeConnection(RelayConnectionKey key) =>
      _connections.closeConnection(key);

  /// Closes every connection, as [closeConnection] does. The manager can still
  /// be used, see [dispose].
  Future<void> closeAllConnections() => _connections.closeAll();

  /// Ends every REQ and publish of this manager, closes its connections and
  /// [relayConnectivityChanges]. Opening a connection, a REQ or a publish on
  /// it afterwards throws a [StateError].
  ///
  /// The REQs still on a connection end as `RelayRequestStatus.disconnected`,
  /// and the relays a publish still waits on fail with
  /// [RelayFailureKind.connectionLost].
  Future<void> dispose() async {
    if (_connections.disposed) return;
    await _connections.dispose();
    await _requests.closeAll();
    _publishes.endAll(
      const RelayFailure(
        RelayFailureKind.connectionLost,
        "the RelayManager was disposed",
      ),
    );
  }

  void _checkNotDisposed() {
    if (_connections.disposed) {
      throw StateError('the RelayManager was disposed');
    }
  }
}

/// Hands what happens to a connection to the REQs, the publishes and the
/// protocol handlers on it.
final class _ConnectionWork implements ConnectionListener {
  final RelayManager _manager;

  _ConnectionWork(this._manager);

  @override
  void onMessage(NostrMessageRaw message, RelayConnection connection) =>
      _manager._dispatch(message, connection);

  @override
  bool hasWorkOn(RelayConnectionKey key) => _manager._connectionHasWork(key);

  @override
  void replayOn(RelayConnection connection) {
    _manager._requests.replayOn(connection);
    _manager._publishes.replayOn(connection);
  }

  @override
  void endAuthRetriesOn(RelayConnectionKey key) =>
      _manager._requests.endAuthRetriesOn(key);

  @override
  void giveUpOn(RelayConnectionKey key) {
    _manager._requests.endRequestsOn(key);
    _manager._publishes.endPublishesOn(key);
  }

  @override
  void admitQueuedOn(RelayConnection connection) =>
      _manager._requests.admitQueuedOn(connection);
}
