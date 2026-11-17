import 'dart:async';
import 'dart:collection';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import 'auth/relay_auth.dart';
import 'config/relay_defaults.dart';
import 'config/request_defaults.dart';
import 'connections/message_length_limit.dart';
import 'connections/relay_connection.dart';
import 'connections/relay_connection_key.dart';
import 'connections/relay_connections.dart';
import 'connections/relay_connectivity.dart';
import 'connections/subscription_limit.dart';
import 'helpers/logger.dart';
import 'helpers/timeout_pausable.dart';
import 'messages/nostr_message_raw.dart';
import 'protocol/relay_protocol_handler.dart';
import 'publishes/publishes_in_flight.dart';
import 'relay_failure.dart';
import 'relay_manager_parts.dart';
import 'reqs/relay_requests.dart';
import 'transport/nostr_transport.dart';

export 'publishes/relay_publish.dart' show RelayPublish, RelayPublishes;
export 'reqs/relay_reqs.dart' show RelayReq, RelayReqs;

/// Opens, keeps and closes the relay connections, and authenticates them
/// (NIP-42). It hands what each relay sends to the REQs and publishes waiting
/// for it.
///
/// Keep one for the whole app, and open REQs and publishes on it with
/// [RelayReqs] and [RelayPublishes].
final class RelayManager {
  late final RelayAuth _auth;
  late final RelayConnections _connections;
  late final RelayRequests _requests;
  late final PublishesInFlight _publishes;

  final List<RelayProtocolHandler> _protocolHandlers = [];

  /// Every connection, each time one is added, starts connecting, opens,
  /// closes or is forgotten. A new listener gets the latest list first.
  ///
  /// A relay can have several connections, so group them by the url of
  /// [RelayConnectivity.key] to show one status per relay.
  Stream<List<RelayConnectivity>> get relayConnectivityChanges =>
      _connections.changes;

  /// Every connection this manager holds, connected or not, as it stands now.
  Map<RelayConnectionKey, RelayConnectivity> get connectivities =>
      Map.unmodifiable({
        for (final MapEntry(:key, :value) in _connections.relays.entries)
          key: value.snapshot(),
      });

  /// The relays this manager does not connect to, see [blockRelay].
  Set<RelayUrl> get blockedRelays =>
      UnmodifiableSetView(_connections.blockedRelays);

  /// Closes the connections to [url], and stops connecting to it.
  Future<void> blockRelay(RelayUrl url) {
    _connections.blockedRelays.add(url);
    return closeConnectionsTo(url);
  }

  /// Lets requests and publishes connect to [url] again.
  void unblockRelay(RelayUrl url) => _connections.blockedRelays.remove(url);

  /// Creates a relay manager.
  ///
  /// [nostrTransportFactory] opens the sockets, usually websockets.
  ///
  /// NIP-42 authentication:
  /// - [accounts] gives the signer of each pubkey, and the logged-in account
  ///   that a request without an `AuthPolicy` may authenticate as.
  /// - [authHandler] is asked before a connection bound to an identity opens.
  /// - [authChallengeTimeout] is how long to wait for the relay's challenge
  ///   once a request needs one.
  /// - [authCallbackTimeout] is how long an AUTH waits for its OK.
  ///
  /// Reconnecting:
  /// - A connection that drops is tried again at once. Each later attempt
  ///   waits 500 milliseconds, then twice as long as the one before, up to
  ///   [reconnectMaximumDelay]. Its requests are replayed once it is back.
  /// - A socket that drops again within 10 seconds of coming back is not
  ///   tried again at once: it waits for the next step.
  /// - After [reconnectGiveUpAfter] without success, its REQs end as
  ///   disconnected and its publishes fail. Null keeps trying.
  /// - A connection that drops with nothing left to do is forgotten rather
  ///   than brought back.
  /// - With [allowReconnect] false, a connection is given up as soon as it
  ///   drops.
  /// - A REQ does not try again a relay it could not reach less than
  ///   [unreachableRelayRetryAfter] ago: it ends there as notSent.
  ///   [Duration.zero] tries every time. A publish always tries again.
  ///
  /// Idle connections:
  /// - A connection with nothing to do closes after [anonymousIdleTimeout],
  ///   or after [authenticatedIdleTimeout] when it is bound to an identity.
  ///   Null keeps it open.
  /// - Nothing to do means nothing that [closeIdleConnections] keeps it for,
  ///   and no message sent or received for that long.
  ///
  /// Limits, asked each time a socket opens:
  /// - [subscriptionLimit] says how many REQs the relay keeps open on one
  ///   socket. The others wait for a slot. Subscriptions leave a quarter of
  ///   the slots to queries, and at least one when there are several. With no
  ///   answer within 2 seconds, the limit is 20, a tenth of what strfry
  ///   accepts: answer it from the relay's NIP-11 document, as `dostr_nip11`
  ///   fetches it.
  /// - [messageLengthLimit] says how many bytes the relay reads in one
  ///   message. A longer message is not sent: a REQ ends there as notSent,
  ///   and an EVENT fails, both with [RelayFailureKind.messageTooLong]. REQs
  ///   and EVENTs wait for the answer.
  /// - A relay that closes a socket with a 1009 reads less than the longest
  ///   message written there. Nothing that long is sent to it again, and
  ///   [onMessageLengthLearned] gets the relay's url and the most bytes it may
  ///   still be sent. Store them and answer [messageLengthLimit] from them
  ///   after a restart, so the limit is not learned again.
  RelayManager({
    required NostrTransportFactory nostrTransportFactory,
    AuthAccounts? accounts,
    bool allowReconnect = true,
    Duration reconnectMaximumDelay = defaultReconnectMaximumDelay,
    Duration? reconnectGiveUpAfter = defaultReconnectGiveUpAfter,
    Duration unreachableRelayRetryAfter = defaultUnreachableRelayRetryAfter,
    Duration? anonymousIdleTimeout = defaultAnonymousIdleTimeout,
    Duration? authenticatedIdleTimeout = defaultAuthenticatedIdleTimeout,
    Duration authCallbackTimeout = defaultAuthCallbackTimeout,
    Duration authChallengeTimeout = defaultAuthChallengeTimeout,
    AuthHandler? authHandler,
    SubscriptionLimit? subscriptionLimit,
    MessageLengthLimit? messageLengthLimit,
    FutureOr<void> Function(RelayUrl url, int length)? onMessageLengthLearned,
  }) {
    for (final (name, duration) in [
      ('reconnectMaximumDelay', reconnectMaximumDelay),
      ('reconnectGiveUpAfter', reconnectGiveUpAfter),
      ('anonymousIdleTimeout', anonymousIdleTimeout),
      ('authenticatedIdleTimeout', authenticatedIdleTimeout),
    ]) {
      if (duration != null && duration <= Duration.zero) {
        throw ArgumentError.value(duration, name, 'must be positive');
      }
    }
    if (unreachableRelayRetryAfter.isNegative) {
      throw ArgumentError.value(
        unreachableRelayRetryAfter,
        'unreachableRelayRetryAfter',
        'must not be negative',
      );
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
      reconnectMaximumDelay: reconnectMaximumDelay,
      reconnectGiveUpAfter: reconnectGiveUpAfter,
      unreachableRelayRetryAfter: unreachableRelayRetryAfter,
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
        protocolHandlers: _protocolHandlers,
      ),
    );
  }

  /// Opens the anonymous connection to [url], and says whether it is
  /// connected, and why not when it is not.
  ///
  /// A refused connection is tried again until [connectTimeout] runs out. One
  /// that dropped is tried now, rather than after its backoff. A connection
  /// bound to an identity opens with [openConnectionAs]. Throws a [StateError]
  /// once disposed.
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

  /// Reconnects every connection that is not connected, even one whose last
  /// attempt just failed, and replays the requests it was carrying. Call it
  /// when the app learns that the network is back.
  Future<void> reconnectClosedConnections() =>
      _connections.reconnectClosedConnections();

  /// Opens the connection to [url] bound to [account].
  ///
  /// Binding it does not authenticate it: it only fixes the one identity the
  /// socket may ever take. A relay sends its challenge when it wants, and some
  /// only do once a request needs it.
  ///
  /// A new binding is first put to the [AuthHandler], with [pausing] paused
  /// while it decides. Reconnecting an existing connection does not ask again.
  /// Throws a [StateError] once disposed.
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

  /// Answers the challenge for [key], and completes once the relay accepted
  /// the AUTH event. Concurrent callers share a single AUTH. False when the
  /// connection is not open.
  Future<bool> authenticateConnection(RelayConnectionKey key) =>
      _connections.isConnectionOpen(key)
      ? _connections.authenticate(key)
      : Future.value(false);

  /// Hands a message from [connection] to whatever it answers.
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
        // a protocol session is not a REQ: it retries on its own, and has no
        // RequestState for the auth-required branch to find
        for (final handler in List.of(_protocolHandlers)) {
          if (handler.onClosed(key, id, closedMsg)) return;
        }
        _requests.handleClosed(id, closedMsg, connection);
      case NostrMessageRawType.auth:
        final eventJson = nostrMsg.otherData;
        final challenge = eventJson[1];
        logger.fine(() => "AUTH challenge from $key: $challenge");

        _auth.sessionOf(connection).receiveChallenge(challenge);

        // an anonymous connection never answers a challenge: signing would bind
        // it to an identity nobody asked for, and make every request already on
        // it attributable. A bound one answers as soon as it can.
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

  /// Closes the connections that carry no work any more.
  ///
  /// Call it when optional subscriptions stop, for example when the app goes
  /// to the background, rather than waiting for the idle timeouts. A live
  /// subscription keeps its connection, even after its EOSE. So does a
  /// connection being opened, authenticated or brought back.
  Future<void> closeIdleConnections() async {
    for (final key in _connections.relays.keys.toList()) {
      // checked again after each close: work may have claimed the next
      // connection while the previous one was closing
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

  /// Closes one connection and forgets it, even one that already lost its
  /// socket. The REQs still open on it end as
  /// `RelayRequestStatus.disconnected`.
  Future<void> closeConnection(RelayConnectionKey key) =>
      _connections.closeConnection(key);

  /// Closes every connection, as [closeConnection] does. The manager can still
  /// be used, see [dispose].
  Future<void> closeAllConnections() => _connections.closeAll();

  /// Ends every REQ and publish of this manager, and closes its connections
  /// and [relayConnectivityChanges]. Opening a connection, a REQ or a publish
  /// on it afterwards throws a [StateError].
  ///
  /// The REQs still on a connection end as `RelayRequestStatus.disconnected`.
  /// The relays a publish still waits on fail with
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

/// Tells the REQs, the publishes and the protocol handlers what happens to
/// their connections.
final class _ConnectionWork implements ConnectionListener {
  final RelayManager _manager;

  _ConnectionWork(this._manager);

  @override
  void onMessage(NostrMessageRaw message, RelayConnection connection) =>
      _manager._dispatch(message, connection);

  @override
  bool hasWorkOn(RelayConnectionKey key) => _manager._connectionHasWork(key);

  @override
  void onBack(RelayConnection connection) {
    _manager._requests.replayOn(connection);
    _manager._publishes.replayOn(connection);
  }

  @override
  void onGone(RelayConnectionKey key) {
    _manager._requests.endRequestsOn(key);
    _manager._publishes.endPublishesOn(key);
  }

  @override
  void admitQueuedOn(RelayConnection connection) =>
      _manager._requests.admitQueuedOn(connection);
}
