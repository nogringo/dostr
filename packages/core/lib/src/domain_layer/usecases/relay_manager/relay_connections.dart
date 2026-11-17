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

  /// checks if the connection identified by [key] is open
  bool isConnectionOpen(RelayConnectionKey key) =>
      relays[key]?.isConnected ?? false;

  /// Whether the connection behind [key] dropped and is being brought back.
  bool isComingBack(RelayConnectionKey key) {
    final connection = relays[key];
    return connection != null && _revivals.isReviving(connection);
  }

  /// Whether nothing will open the connection behind [key] again.
  bool isGone(RelayConnectionKey key) =>
      !isConnectionOpen(key) && !isComingBack(key);

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

  /// Opens the connection behind [key] unless it is open already, and says
  /// what came of it. A bound one comes back bound or not at all.
  ///
  /// One that dropped and is being brought back is left to its backoff. One
  /// that failed to open less than [unreachableRelayRetryAfter] ago is not
  /// tried again, unless [retryUnreachable].
  ///
  /// [as] is the identity to open a bound connection as, for a caller that has
  /// it in hand. Without it the account is looked up, which only works for a
  /// registered one or one the connection was opened as before.
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
    final current = _openingNow(key);
    if (current != null) return current;
    final connection = relays[key];
    if (!retryUnreachable &&
        connection != null &&
        connection.opening == null &&
        connection.relay.failedWithin(unreachableRelayRetryAfter)) {
      return NotOpened(
        RelayFailure(
          RelayFailureKind.unreachable,
          "failed less than ${unreachableRelayRetryAfter.inSeconds} seconds ago",
        ),
      );
    }
    final failure = await _open(
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
    if (connection == null) return null;
    if (connection.isConnected) return Opened(connection);
    return _revivals.isReviving(connection) ? const ComingBack() : null;
  }

  /// Opens the connection behind [key] now, whatever its last attempt, and
  /// says why it could not. One that is being brought back is tried now
  /// instead of after its backoff. See [ensureOpen] for [as].
  Future<RelayFailure?> connectNow(
    RelayConnectionKey key, {
    NostrSigner? as,
    TimeoutPausable? pausing,
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) {
    if (blockedRelays.contains(key.url)) {
      return Future.value(const RelayFailure(RelayFailureKind.blocked));
    }
    final connection = relays[key];
    if (connection != null && _revivals.isReviving(connection)) {
      return _revivals.hurry(connection);
    }
    return _open(key, as: as, pausing: pausing, connectTimeout: connectTimeout);
  }

  /// Opens the connection behind [key], created when it is new, and says why
  /// it could not.
  ///
  /// A bound one opens as [as], or as the account it is known by. The binding
  /// says which identity this socket may ever assume, not that it is already
  /// authenticated: relays are free to send their challenge whenever they
  /// want, and some only send it once a request needs it. A new binding is
  /// first put to the `AuthHandler`, with [pausing] paused while it decides.
  Future<RelayFailure?> _open(
    RelayConnectionKey key, {
    NostrSigner? as,
    TimeoutPausable? pausing,
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    if (!key.isAnonymous) {
      final account =
          as ?? _auth.accountFor(key, openedAs: relays[key]?.account);
      if (account == null || !account.canSign) {
        logger.warning(() => "No account that can sign to open $key");
        return const RelayFailure(RelayFailureKind.noBoundConnection);
      }
      if (relays[key] == null && !await _auth.consent(key, pausing: pausing)) {
        logger.fine(() => "Not allowed to open $key");
        return const RelayFailure(RelayFailureKind.noBoundConnection);
      }
      _connectionFor(key).account = account;
    }
    return reopen(_connectionFor(key), connectTimeout: connectTimeout);
  }

  RelayConnection _connectionFor(RelayConnectionKey key) =>
      relays.putIfAbsent(key, () => RelayConnection(key));

  /// Opens a socket for [connection] unless it has one open, or waits for the
  /// one being opened, and says why it could not.
  Future<RelayFailure?> reopen(
    RelayConnection connection, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) {
    if (blockedRelays.contains(connection.url)) {
      return Future.value(const RelayFailure(RelayFailureKind.blocked));
    }
    if (connection.isConnected) return Future.value();
    return connection.opening ??= _openSocket(
      connection,
      connectTimeout,
    ).whenComplete(() => connection.opening = null);
  }

  /// Opens a new socket for [connection], tried again on a refusal until
  /// [connectTimeout] runs out, and says why it could not.
  Future<RelayFailure?> _openSocket(
    RelayConnection connection,
    Duration connectTimeout,
  ) async {
    final key = connection.key;
    final url = key.url;
    NostrTransport? transport;
    bool ownsTransport() => _isCurrent(connection, transport);

    connection.relay.tryingToConnect();
    notifyChanged();
    connection.idleFor.reset();
    _idle.watch();
    logger.info(() => "connecting to relay $url");
    try {
      // A disconnected transport may still own reconnect timers and listeners.
      // Retire it before replacement or it can later open an untracked socket.
      await connection.close();
      if (!identical(relays[key], connection)) {
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
        if (!identical(relays[key], connection)) {
          throw StateError('Connection was removed while connecting');
        }
      }
    } catch (error) {
      logger.severe(() => "!! could not connect to $url -> $error");
      if (transport == null ||
          identical(connection.relayTransport, transport)) {
        await connection.close();
      } else {
        await transport.close().catchError((Object closeError) {
          logger.warning(
            () => "Error retiring transport for $url: $closeError",
          );
        });
      }
      connection.relay.failedToConnect();
      connection.stats.connectionErrors++;
      notifyChanged();
      return RelayFailure(RelayFailureKind.unreachable, "$error");
    }
    logger.info(() => "connected to relay: $url");
    connection.relay.succeededToConnect();
    connection.stats.connections++;
    notifyChanged();
    return null;
  }

  /// Waits until the connection behind [key] is back from its drop, or given
  /// up, and says whether it is open.
  Future<bool> whenBack(RelayConnectionKey key) async {
    while (true) {
      final connection = relays[key];
      final settled = connection == null ? null : _revivals.settled(connection);
      if (settled == null) return isConnectionOpen(key);
      await settled;
    }
  }

  /// Answers the challenge for [key] and completes once the relay accepted the
  /// AUTH event. Concurrent callers share a single AUTH.
  Future<bool> authenticate(RelayConnectionKey key) {
    final connection = relays[key];
    if (key.isAnonymous || connection == null) {
      return Future.value(false);
    }
    return _auth.authenticate(
      connection,
      (message) => sendTo(connection, message),
    );
  }

  /// Reconnects every connection that is not connected, all at once, even one
  /// that just failed to, and replays the requests it was carrying.
  Future<void> reconnectClosedConnections() => Future.wait([
    for (final connection in relays.values.toList())
      if (!connection.isConnected) _reconnect(connection),
  ]);

  Future<void> _reconnect(RelayConnection connection) async {
    // a revival replays on its own once it is back
    final replays = !_revivals.isReviving(connection);
    if (await connectNow(connection.key) == null && replays) {
      listener.replayOn(connection);
    }
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
  void _handleTransportGone(
    RelayConnection connection,
    NostrTransport? transport,
  ) {
    // a socket that ends while it opens is a failed connect, which _openSocket
    // reports and the backoff retries: reviving it here would skip that wait
    if (!_isCurrent(connection, transport) || connection.opening != null) {
      return;
    }
    final key = connection.key;
    connection.stats.connectionErrors++;
    if (transport?.closeCode() == ws_status.messageTooBig) {
      _limits.learnFrom(connection);
    }
    // the AUTH the relay accepted died with the socket, and so did any still
    // waiting for its OK
    final retired = connection.close();
    if (!hasWorkOn(key)) {
      logger.info(() => "closed $key, nothing left on it");
      unawaited(closeConnection(key));
      return;
    }
    notifyChanged();
    // deliberate closes cancel the stream subscription first and never get here
    if (allowReconnect) {
      logger.info(() => "closed ${connection.url}. Reconnecting");
      _revivals.comeBack(connection, retired);
      return;
    }
    _revivals.stop(connection);
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
  Future<void> closeConnection(RelayConnectionKey key) {
    final connection = relays.remove(key);
    if (connection == null) return Future.value();
    notifyChanged();
    logger.fine(() => "Disconnecting $key...");
    _revivals.stop(connection);
    final closing = connection.close();
    listener.endAuthRetriesOn(key);
    listener.endRequestsOn(key);
    return closing;
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
