import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../../config/relay_defaults.dart';
import '../../../shared/helpers/utf8_length.dart';
import '../../../shared/logger.dart';
import '../../../shared/nips/nip01/client_msg.dart';
import '../../../shared/nips/nip01/decode_nostr_msg.dart';
import '../../../shared/nips/nip01/nostr_message_raw.dart';
import '../../entities/message_length_limit.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_failure.dart';
import '../../entities/subscription_limit.dart';
import '../../entities/timeout_pausable.dart';
import '../../repositories/nostr_transport.dart';
import 'backoff.dart';
import 'idle_connections.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'relay_limits.dart';
import 'relay_revivals.dart';

/// What the work riding on the connections of [RelayConnections] has to do
/// when a socket comes back or goes away.
abstract interface class ConnectionListener {
  /// Puts back on [connection] what the socket it replaces still owed.
  void replayOn(RelayConnection connection);

  /// Gives up on what was waiting for [key] to replay it after an
  /// authentication.
  void endAuthRetriesOn(RelayConnectionKey key);

  /// Gives up on what [key] still owed, once nothing will bring it back.
  void endRequestsOn(RelayConnectionKey key);

  /// Writes the queued REQs that now fit on [connection]: a slot was freed
  /// there, or its limit became known.
  void admitQueuedOn(RelayConnection connection);
}

/// What [RelayConnections.ensureOpen] came to for a connection.
sealed class Opening {
  const Opening();
}

/// The connection is open.
final class Opened extends Opening {
  final RelayConnection connection;

  const Opened(this.connection);
}

/// The connection dropped and is being brought back, on its own backoff.
final class ComingBack extends Opening {
  const ComingBack();
}

/// The connection could not be opened.
final class NotOpened extends Opening {
  final RelayFailure failure;

  const NotOpened(this.failure);
}

/// A decoded relay message, in the order its relay sent it.
typedef RelayMessageHandler =
    void Function(
      NostrMessageRaw message,
      RelayConnection connection,
      String raw,
    );

/// The connections of a `RelayManager`: opening, reconnecting and closing them,
/// writing to them and reading from them. Internal to dostr_core.
///
/// It is the only thing that reconnects: a transport is a single socket.
class RelayConnections {
  final NostrTransportFactory nostrTransportFactory;
  final RelayAuth _auth;
  final RelayMessageHandler _onMessage;

  /// whether something still needs the connection behind a key: one that
  /// drops without is forgotten instead of brought back
  final bool Function(RelayConnectionKey key) hasWorkOn;
  final int _reconnectMaximumStep;
  late final RelayLimits _limits;
  late final IdleConnections _idle;
  late final RelayRevivals _revivals = RelayRevivals(
    this,
    maximumStep: _reconnectMaximumStep,
  );

  /// told when a socket comes back or goes away, set before any connection
  late final ConnectionListener listener;

  /// Are reconnects allowed when a connection drops?
  bool allowReconnect;

  /// touched relays - connected, connecting, disconnected
  /// key: relay url and identity bound to the connection
  /// value: relay connection
  final Map<RelayConnectionKey, RelayConnection> relays = {};

  /// relays that are blocked
  final Set<RelayUrl> blockedRelays = {};

  /// Tracks relay connect attempts that are still finishing setup so callers
  /// can wait for "socket open + listener attached", not just raw socket open.
  final Map<
    RelayConnectionKey,
    Completer<({bool connected, RelayFailure? failure})>
  >
  _connectReadyCompleters = {};

  /// connections whose socket just died, until it is settled whether they come
  /// back
  final Map<RelayConnectionKey, Completer<void>> _dropping = {};

  final _updates = BehaviorSubject<List<RelayConnection>>();

  List<({RelayConnectionKey key, bool connected, bool connecting})>? _notified;

  RelayConnections({
    required this.nostrTransportFactory,
    required RelayAuth auth,
    required RelayMessageHandler onMessage,
    required this.hasWorkOn,
    Duration? anonymousIdleTimeout,
    Duration? authenticatedIdleTimeout,
    this.allowReconnect = true,
    int reconnectMaximumStep = defaultReconnectMaximumStep,
    SubscriptionLimit? subscriptionLimit,
    MessageLengthLimit? messageLengthLimit,
    FutureOr<void> Function(RelayUrl url, int length)? onMessageLengthLearned,
  }) : _auth = auth,
       _onMessage = onMessage,
       _reconnectMaximumStep = reconnectMaximumStep {
    _limits = RelayLimits(
      onKnown: (connection) => listener.admitQueuedOn(connection),
      subscriptionLimit: subscriptionLimit,
      messageLengthLimit: messageLengthLimit,
      onMessageLengthLearned: onMessageLengthLearned,
    );
    _idle = IdleConnections(
      this,
      anonymousTimeout: anonymousIdleTimeout,
      authenticatedTimeout: authenticatedIdleTimeout,
    );
  }

  /// every connection each time one is added, starts connecting, opens,
  /// closes or is forgotten, the latest one cached
  Stream<List<RelayConnection>> get changes => _updates.stream;

  /// Tells [changes], unless no connection changed since it last did.
  void notifyChanged() {
    final connections = relays.values.toList();
    final states = [
      for (final connection in connections)
        (
          key: connection.key,
          connected: connection.isConnected,
          connecting: connection.relay.connecting,
        ),
    ];
    final notified = _notified;
    if (notified != null &&
        notified.length == states.length &&
        Iterable<int>.generate(
          states.length,
        ).every((i) => notified[i] == states[i])) {
      return;
    }
    _notified = states;
    _updates.add(connections);
  }

  /// Every open connection, anonymous or bound, so a relay can show up more
  /// than once.
  List<RelayConnection> get connectedRelays =>
      relays.values.where((connection) => connection.isConnected).toList();

  /// Whether the anonymous connection to [url] is open.
  bool isRelayConnected(RelayUrl url) =>
      isConnectionOpen(RelayConnectionKey.anonymous(url));

  /// checks if the connection identified by [key] is open
  bool isConnectionOpen(RelayConnectionKey key) =>
      relays[key]?.relayTransport?.isOpen() ?? false;

  /// Whether the connection behind [key] dropped and is being brought back.
  bool isComingBack(RelayConnectionKey key) =>
      _dropping.containsKey(key) || _revivals.isReviving(key);

  /// Whether nothing will open the connection behind [key] again.
  bool isGone(RelayConnectionKey key) =>
      !isConnectionOpen(key) && !isComingBack(key);

  /// Whether a socket for [key] is still being opened.
  bool isOpening(RelayConnectionKey key) {
    final connection = relays[key];
    return _connectReadyCompleters.containsKey(key) ||
        (connection?.relay.connecting ?? false) ||
        (connection?.relayTransport?.isConnecting() ?? false);
  }

  /// The anonymous connection to [url], if there is one.
  RelayConnection? getRelayConnectivity(RelayUrl url) =>
      relays[RelayConnectionKey.anonymous(url)];

  /// every connection currently held towards [url]
  List<RelayConnectionKey> keysFor(RelayUrl url) =>
      relays.keys.where((key) => key.url == url).toList();

  /// Waits up to [timeout] for [transport] to open, and returns why it did not.
  static Future<Object?> _whyNotOpen(
    NostrTransport transport,
    Duration timeout,
  ) async {
    if (!transport.isOpen()) {
      try {
        await transport.ready.timeout(timeout);
      } catch (error) {
        return error;
      }
    }
    return transport.isOpen() ? null : StateError("closed once ready");
  }

  /// Connects to a relay to the relay pool.
  /// Returns whether it is connected, and why if it is not.
  Future<({bool connected, RelayFailure? failure})> connectRelay(
    RelayUrl url, {
    String? authPubkey,
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    if (blockedRelays.contains(url)) {
      return (
        connected: false,
        failure: const RelayFailure(RelayFailureKind.blocked),
      );
    }

    final connectionKey = authPubkey == null
        ? RelayConnectionKey.anonymous(url)
        : RelayConnectionKey.authenticated(url, authPubkey);

    if (isConnectionOpen(connectionKey)) {
      logger.finest(() => "relay already connected: $connectionKey");
      return (connected: true, failure: null);
    }

    final inFlightConnect = _connectReadyCompleters[connectionKey];
    if (inFlightConnect != null) {
      logger.finest(() => "relay is already connecting: $connectionKey");
      return inFlightConnect.future;
    }
    RelayConnection? connection = relays[connectionKey];
    final connectCompleter =
        Completer<({bool connected, RelayFailure? failure})>();
    _connectReadyCompleters[connectionKey] = connectCompleter;
    NostrTransport? transport;
    bool ownsTransport() => _isCurrent(connection, transport);
    Object? failure;

    try {
      if (connection == null) {
        connection = RelayConnection(connectionKey);
        relays[connectionKey] = connection;
      }

      connection.relay.tryingToConnect();
      notifyChanged();
      connection.idleFor.reset();
      _idle.watch();

      logger.info(() => "connecting to relay $url");

      // a fresh socket for a key we may already know: nothing the previous one
      // authenticated carries over
      _auth.forget(connectionKey);
      // A disconnected transport may still own reconnect timers and listeners.
      // Retire it before replacement or it can later open an untracked socket.
      await connection.close();
      if (!identical(relays[connectionKey], connection)) {
        throw StateError(
          'Connection was removed while replacing its transport',
        );
      }
      _limits.ask(connection);
      final elapsed = Stopwatch()..start();
      final backoff = BinaryExponentialBackoff(
        initial: reconnectInitialDelay,
        maximumStep: _reconnectMaximumStep,
      );
      while (true) {
        transport = nostrTransportFactory(url);
        connection.relayTransport = transport;
        // Start listening immediately so we don't miss early frames such as
        // relay AUTH challenges that may arrive before the transport reports
        // itself fully open.
        _startListeningToSocket(connection);
        final notOpen = await _whyNotOpen(
          transport,
          connectTimeout - elapsed.elapsed,
        );
        if (!ownsTransport()) {
          throw StateError("connection replaced while connecting");
        }
        if (notOpen == null) break;
        // a refusal is tried again until connectTimeout runs out
        final wait = backoff.next();
        if (elapsed.elapsed + wait >= connectTimeout) throw notOpen;
        await connection.close();
        await Future<void>.delayed(wait);
        if (!identical(relays[connectionKey], connection)) {
          throw StateError('Connection was removed while connecting');
        }
      }

      logger.info(() => "connected to relay: $url");
      connection.relay.succeededToConnect();
      connection.stats.connections++;
      final connected = (connected: true, failure: null);
      if (!connectCompleter.isCompleted) {
        connectCompleter.complete(connected);
      }
      if (identical(_connectReadyCompleters[connectionKey], connectCompleter)) {
        _connectReadyCompleters.remove(connectionKey);
      }
      notifyChanged();
      // opened by someone else while waiting for its next attempt: replay now
      if (_revivals.isWaiting(connectionKey)) {
        unawaited(_revivals.revive(connection));
      }
      return connected;
    } catch (e) {
      failure = e;
      logger.severe(() => "!! could not connect to $url -> $failure");
      try {
        if (transport == null ||
            identical(connection!.relayTransport, transport)) {
          await connection!.close();
        } else {
          await transport.close();
        }
      } catch (closeError) {
        logger.warning(() => "Error retiring transport for $url: $closeError");
      }
    }
    final failedConnection = connection;
    if (failedConnection != null) {
      failedConnection.relay.failedToConnect();
      failedConnection.stats.connectionErrors++;
    }
    final failed = (
      connected: false,
      failure: RelayFailure(RelayFailureKind.unreachable, "$failure"),
    );
    if (!connectCompleter.isCompleted) {
      connectCompleter.complete(failed);
    }
    if (identical(_connectReadyCompleters[connectionKey], connectCompleter)) {
      _connectReadyCompleters.remove(connectionKey);
    }
    notifyChanged();
    return failed;
  }

  /// Opens the connection behind [key] unless it is open already, and says
  /// what came of it. A bound one comes back bound or not at all.
  ///
  /// One that dropped and is being brought back is left to its backoff. One
  /// that failed to open less than [unreachableRelayRetryAfter] ago is not
  /// tried again, unless [retryUnreachable].
  ///
  /// [as] is the identity to open a bound connection as, for a caller that has
  /// it in hand. Without it the account is looked up, which only works for a
  /// registered one.
  Future<Opening> ensureOpen(
    RelayConnectionKey key, {
    NostrSigner? as,
    TimeoutPausable? pausing,
    Duration connectTimeout = defaultWebSocketConnectTimeout,
    bool retryUnreachable = false,
  }) async {
    if (blockedRelays.contains(key.url)) {
      return const NotOpened(RelayFailure(RelayFailureKind.blocked));
    }
    final inFlight = _connectReadyCompleters[key];
    if (inFlight != null) {
      final (connected: _, :failure) = await inFlight.future;
      return _openingNow(key) ??
          NotOpened(
            failure ?? const RelayFailure(RelayFailureKind.connectionLost),
          );
    }
    final current = _openingNow(key);
    if (current != null) return current;
    final tried = relays[key]?.relay;
    if (!retryUnreachable &&
        tried != null &&
        tried.failedWithin(unreachableRelayRetryAfter)) {
      return NotOpened(
        RelayFailure(
          RelayFailureKind.unreachable,
          "failed less than ${unreachableRelayRetryAfter.inSeconds} seconds ago",
        ),
      );
    }
    final failure = await openNow(
      key,
      as: as,
      pausing: pausing,
      connectTimeout: connectTimeout,
    );
    return _openingNow(key) ??
        NotOpened(
          failure ?? const RelayFailure(RelayFailureKind.connectionLost),
        );
  }

  Opening? _openingNow(RelayConnectionKey key) {
    final connection = relays[key];
    if (connection != null && connection.isConnected) {
      return Opened(connection);
    }
    return isComingBack(key) ? const ComingBack() : null;
  }

  /// Opens the connection behind [key] now, whatever its last attempt, and
  /// says why it could not. Only what brings connections back skips
  /// [ensureOpen] this way.
  Future<RelayFailure?> openNow(
    RelayConnectionKey key, {
    NostrSigner? as,
    TimeoutPausable? pausing,
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    if (key.isAnonymous) {
      return (await connectRelay(
        key.url,
        connectTimeout: connectTimeout,
      )).failure;
    }
    final account = as ?? _auth.accountFor(key);
    if (account == null) {
      logger.warning(() => "No account left to open $key");
      return const RelayFailure(RelayFailureKind.noBoundConnection);
    }
    final bound = await openConnectionAs(
      key.url,
      account,
      connectTimeout: connectTimeout,
      pausing: pausing,
    );
    return bound == null
        ? const RelayFailure(RelayFailureKind.noBoundConnection)
        : null;
  }

  /// Waits until the connection behind [key] is back from its drop, or given
  /// up, and says whether it is open.
  Future<bool> whenBack(RelayConnectionKey key) async {
    while (true) {
      final dropping = _dropping[key];
      if (dropping != null) {
        await dropping.future;
        continue;
      }
      final settled = _revivals.settled(key);
      if (settled == null) return isConnectionOpen(key);
      await settled;
    }
  }

  /// Opens the connection towards [url] bound to [account]. The binding says
  /// which identity this socket may ever assume, not that it is already
  /// authenticated: relays are free to send their challenge whenever they want,
  /// and some only send it once a request needs it.
  ///
  /// A new binding is first put to the `AuthHandler`, with [pausing] paused
  /// while it decides. A connection that already exists was agreed to when it
  /// was first opened, so reconnecting it does not ask again.
  Future<RelayConnection?> openConnectionAs(
    RelayUrl url,
    NostrSigner account, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
    TimeoutPausable? pausing,
  }) async {
    if (!account.canSign) {
      logger.warning(() => "Cannot bind a connection to ${account.publicKey}");
      return null;
    }
    final key = RelayConnectionKey.authenticated(url, account.publicKey);
    if (relays[key] == null && !await _auth.consent(key, pausing: pausing)) {
      logger.fine(() => "Not allowed to open $key");
      return null;
    }
    _auth.bind(key, account);

    if (isConnectionOpen(key)) {
      return relays[key];
    }

    final result = await connectRelay(
      url,
      authPubkey: account.publicKey,
      connectTimeout: connectTimeout,
    );
    final connection = relays[key];
    if (!result.connected || connection == null) {
      logger.warning(() => "Could not open $key: ${result.failure}");
      return null;
    }
    return connection;
  }

  /// Answers the challenge for [key] and completes once the relay accepted the
  /// AUTH event. Concurrent callers share a single AUTH.
  Future<bool> authenticate(RelayConnectionKey key) {
    final connection = relays[key];
    if (key.isAnonymous || connection == null) {
      return Future.value(false);
    }
    return _auth.authenticate(key, (message) => sendTo(connection, message));
  }

  /// Reconnects every connection that is not connected, all at once, even one
  /// that just failed to, and replays the requests it was carrying.
  Future<void> reconnectClosedConnections() => Future.wait([
    for (final connection in relays.values.toList())
      if (!connection.isConnected) _reconnectNow(connection),
  ]);

  Future<void> _reconnectNow(RelayConnection connection) async {
    if (_revivals.isReviving(connection.key)) {
      await _revivals.revive(connection);
      return;
    }
    if (await openNow(connection.key) == null) listener.replayOn(connection);
  }

  /// Writes [data] and tells whether it reached the transport
  bool _sendRaw(
    RelayConnection connection,
    NostrTransport transport,
    dynamic data,
  ) {
    if (!identical(connection.relayTransport, transport) ||
        !transport.isOpen()) {
      logger.finest(
        () => "skip send to ${connection.url}: transport changed or closed",
      );
      return false;
    }
    transport.send(data);
    connection.idleFor.reset();
    logger.fine(() => "send message to ${connection.url}: $data");
    return true;
  }

  /// Sends [message] and surfaces transport churn/closed-socket failures to
  /// the caller instead of silently dropping the write.
  Future<void> sendOrThrow(
    RelayConnection connection,
    List<dynamic> message,
  ) async {
    NostrTransport? transport = connection.relayTransport;
    if (transport == null) {
      throw StateError("relay not connected: ${connection.url}");
    }

    await transport.ready;

    if (!identical(connection.relayTransport, transport) ||
        !transport.isOpen()) {
      transport = connection.relayTransport;
      if (transport == null) {
        throw StateError(
          "transport changed while waiting for ${connection.url}",
        );
      }

      await transport.ready;

      if (!identical(connection.relayTransport, transport) ||
          !transport.isOpen()) {
        throw StateError(
          "transport changed while waiting for ${connection.url}",
        );
      }
    }

    // a REQ already waited for them in its queue
    if (message.first == ClientMsgType.kEvent) {
      await connection.limitsKnown.future;
    }
    final String encodedMsg = jsonEncode(message);
    if (!identical(connection.relayTransport, transport) ||
        !transport.isOpen()) {
      throw StateError("transport closed before send: ${connection.url}");
    }
    final length = utf8Length(encodedMsg);
    _limits.check(connection, length);
    if (_sendRaw(connection, transport, encodedMsg)) {
      connection.longestMessage = max(connection.longestMessage, length);
      _countRequest(connection, message);
    }
  }

  /// Keeps the open requests of a connection on the connection that carries
  /// them: a REQ re-routed to another one is not accounted here.
  void _countRequest(RelayConnection connection, List<dynamic> message) {
    switch (message) {
      case [ClientMsgType.kReq, final String id, ...]:
        connection.stats.openRequestIds.add(id);
      case [ClientMsgType.kClose, final String id, ...]:
        if (connection.stats.openRequestIds.remove(id)) {
          listener.admitQueuedOn(connection);
        }
    }
  }

  /// Sends [message] on the connection behind [key] once its socket is ready,
  /// see [sendTo].
  void send(RelayConnectionKey key, List<dynamic> message) {
    final connection = relays[key];
    if (connection == null) {
      logger.finest(() => "skip send to $key: no such connection");
      return;
    }
    sendTo(connection, message);
  }

  /// Sends [message] on [connection] once its socket is ready. It is
  /// dropped, and logged, when that socket goes away first.
  void sendTo(RelayConnection connection, List<dynamic> message) {
    unawaited(
      sendOrThrow(connection, message).catchError((Object error) {
        if (error is MessageTooLong) {
          logger.warning(() => "skip send to ${connection.url}: $error");
        } else {
          logger.finest(() => "skip send to ${connection.url}: $error");
        }
      }),
    );
  }

  /// Whether [connection] is still the connection tracked under its key, and
  /// [transport] still the one it runs on: anything a replaced one reports is
  /// stale.
  bool _isCurrent(RelayConnection? connection, NostrTransport? transport) =>
      connection != null &&
      transport != null &&
      identical(relays[connection.key], connection) &&
      identical(connection.relayTransport, transport);

  void _startListeningToSocket(RelayConnection connection) {
    final transport = connection.relayTransport;
    connection.listen(
      (message) {
        if (!_isCurrent(connection, transport)) return;
        _handleIncomingMessage(message, connection);
      },
      onError: (error) {
        if (!_isCurrent(connection, transport)) return;
        logger.severe(() => "onError ${connection.url} on listen $error");
        _handleTransportGone(connection, transport);
      },
      onDone: () {
        logger.finest(
          () =>
              "onDone ${connection.url} on listen (close: ${connection.relayTransport?.closeCode()} ${connection.relayTransport?.closeReason()})",
        );
        _handleTransportGone(connection, transport);
      },
    );
  }

  /// Cleans up after [transport] died and brings the connection back, or
  /// forgets it when nothing needs it any more. Both ways a socket can end land
  /// here: an error cancels the stream subscription, so the done event that
  /// would otherwise follow never arrives.
  ///
  /// Runs once per transport, so a late event from a socket that was already
  /// replaced leaves the current one alone.
  Future<void> _handleTransportGone(
    RelayConnection connection,
    NostrTransport? transport,
  ) async {
    if (!_isCurrent(connection, transport)) return;
    final key = connection.key;
    // a socket that ends while it opens is a failed connect, which connectRelay
    // reports and the backoff retries: reviving it here would skip that wait
    if (_connectReadyCompleters.containsKey(key)) return;
    connection.stats.connectionErrors++;
    if (transport?.closeCode() == ws_status.messageTooBig) {
      _limits.learnFrom(connection);
    }
    // the AUTH the relay accepted died with the socket, and so did any still
    // waiting for its OK
    _auth.forget(key);

    final dropped = _dropping[key] = Completer();
    try {
      await connection.close();
    } catch (e) {
      logger.warning(() => "Error closing relay ${connection.url}: $e");
    } finally {
      if (identical(_dropping[key], dropped)) _dropping.remove(key);
      dropped.complete();
    }
    // Closing can yield while a new owner or transport takes over. Its AUTH
    // and subscriptions belong to the replacement, not this retired socket.
    if (!identical(relays[key], connection) ||
        connection.relayTransport != null) {
      return;
    }
    if (!hasWorkOn(key)) {
      logger.info(() => "closed $key, nothing left on it");
      await closeConnection(key);
      return;
    }
    notifyChanged();
    // deliberate closes cancel the stream subscription first and never get here
    if (allowReconnect) {
      logger.info(() => "closed ${connection.url}. Reconnecting");
      if (!_revivals.resume(connection)) {
        unawaited(_revivals.revive(connection));
      }
      return;
    }
    _revivals.forgetRevived(key);
    listener.endAuthRetriesOn(key);
    listener.endRequestsOn(key);
  }

  void _handleIncomingMessage(dynamic message, RelayConnection connection) {
    connection.idleFor.reset();
    if (message is! String) {
      logger.warning(() => "Ignoring a non-text frame from ${connection.url}");
      return;
    }
    // a relay controls what it sends: nothing it sends may throw out of here,
    // where it would kill a process that has no zone to catch it
    try {
      _onMessage(decodeNostrMsg(message), connection, message);
    } catch (error, stackTrace) {
      logger.severe(
        () => "Could not handle a message from ${connection.url}: $message",
        error,
        stackTrace,
      );
    }
  }

  /// Closes one connection and forgets it. An entry that lost its transport, to
  /// a reset or to a failed connection attempt, is forgotten just the same:
  /// leaving it behind keeps its auth state alive and makes it reconnect.
  Future<void> closeConnection(RelayConnectionKey key) async {
    final connection = relays.remove(key);
    if (connection == null) {
      return;
    }
    notifyChanged();
    logger.fine(() => "Disconnecting $key...");
    _revivals.stop(key);
    _auth.unbind(key);
    _auth.forget(key);
    listener.endAuthRetriesOn(key);
    listener.endRequestsOn(key);
    return connection.close();
  }

  /// Closes all transports
  Future<void> closeAll() async {
    _idle.stop();
    final keys = relays.keys.toList();
    try {
      await Future.wait(keys.map(closeConnection));
    } catch (e) {
      logger.severe(() => e);
    }
  }
}
