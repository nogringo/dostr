import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../auth/relay_auth.dart';
import '../config/relay_defaults.dart';
import '../helpers/logger.dart';
import '../helpers/timeout_pausable.dart';
import '../helpers/utf8_length.dart';
import '../messages/decode_nostr_msg.dart';
import '../messages/nostr_message_raw.dart';
import '../relay_failure.dart';
import '../transport/nostr_transport.dart';
import 'backoff.dart';
import 'idle_connections.dart';
import 'message_length_limit.dart';
import 'relay_connection.dart';
import 'relay_connection_key.dart';
import 'relay_connectivity.dart';
import 'relay_limits.dart';
import 'relay_revivals.dart';
import 'subscription_limit.dart';

/// The work that runs on the connections of [RelayConnections]. It is told
/// what happens to each connection, and asked whether it still needs one.
abstract interface class ConnectionListener {
  /// A decoded message from [connection], in the order its relay sent it.
  void onMessage(NostrMessageRaw message, RelayConnection connection);

  /// Whether something still needs the connection behind [key]. A connection
  /// nothing needs is forgotten when it drops, rather than brought back.
  bool hasWorkOn(RelayConnectionKey key);

  /// [connection] has a new socket, which must get again what the old one
  /// still owed.
  void onBack(RelayConnection connection);

  /// Nothing will bring the connection behind [key] back.
  void onGone(RelayConnectionKey key);

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

/// The connections of a `RelayManager`. Internal to dostr_core.
///
/// It opens, reconnects and closes them, and writes to and reads from them. It
/// is the only thing that reconnects: a transport is a single socket.
class RelayConnections {
  final NostrTransportFactory nostrTransportFactory;
  final RelayAuth _auth;
  final Duration _reconnectMaximumDelay;
  final Duration _unreachableRelayRetryAfter;
  late final RelayLimits _limits;
  late final IdleConnections _idle;
  late final RelayRevivals _revivals;

  final ConnectionListener listener;

  /// Whether a connection that drops is brought back.
  final bool allowReconnect;

  /// Every connection, connected or not, by relay and identity.
  final Map<RelayConnectionKey, RelayConnection> relays = {};

  final Set<RelayUrl> blockedRelays = {};

  final _updates = BehaviorSubject<List<RelayConnectivity>>();

  bool _disposed = false;

  /// Whether [dispose] was called: no connection opens any more.
  bool get disposed => _disposed;

  static const _disposedFailure = RelayFailure(
    RelayFailureKind.connectionLost,
    "the RelayManager was disposed",
  );

  bool _suspended = false;
  Completer<void> _resumed = Completer()..complete();

  /// Whether [suspend] was called without a [resume] since: no socket opens.
  bool get suspended => _suspended;

  static const _suspendedFailure = RelayFailure(
    RelayFailureKind.connectionLost,
    "the RelayManager is suspended",
  );

  List<({RelayConnectionKey key, bool connected, bool connecting})>? _notified;

  RelayConnections({
    required this.nostrTransportFactory,
    required RelayAuth auth,
    required this.listener,
    Duration? anonymousIdleTimeout,
    Duration? authenticatedIdleTimeout,
    this.allowReconnect = true,
    Duration reconnectMaximumDelay = defaultReconnectMaximumDelay,
    Duration? reconnectGiveUpAfter = defaultReconnectGiveUpAfter,
    Duration unreachableRelayRetryAfter = defaultUnreachableRelayRetryAfter,
    SubscriptionLimit? subscriptionLimit,
    MessageLengthLimit? messageLengthLimit,
    FutureOr<void> Function(RelayUrl url, int length)? onMessageLengthLearned,
  }) : _auth = auth,
       _reconnectMaximumDelay = reconnectMaximumDelay,
       _unreachableRelayRetryAfter = unreachableRelayRetryAfter {
    _revivals = RelayRevivals(
      this,
      maximumDelay: reconnectMaximumDelay,
      giveUpAfter: reconnectGiveUpAfter,
    );
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

  /// See [ConnectionListener.hasWorkOn].
  bool hasWorkOn(RelayConnectionKey key) => listener.hasWorkOn(key);

  /// Every connection, each time one is added, starts connecting, opens,
  /// closes or is forgotten. A new listener gets the latest list first.
  Stream<List<RelayConnectivity>> get changes => _updates.stream;

  /// Tells [changes], unless no connection changed since it last did.
  void notifyChanged() {
    if (_updates.isClosed) return;
    final connections = relays.values.toList();
    final states = [
      for (final connection in connections)
        (
          key: connection.key,
          connected: connection.isConnected,
          connecting: connection.attempts.connecting,
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
    _updates.add([for (final connection in connections) connection.snapshot()]);
  }

  /// Every open connection, anonymous or bound, so a relay can show up more
  /// than once.
  List<RelayConnection> get connectedRelays =>
      relays.values.where((connection) => connection.isConnected).toList();

  /// Whether the connection behind [key] is open.
  bool isConnectionOpen(RelayConnectionKey key) =>
      relays[key]?.isConnected ?? false;

  /// Whether the connection behind [key] dropped and is being brought back,
  /// or waits for [resume].
  bool isComingBack(RelayConnectionKey key) {
    final connection = relays[key];
    return connection != null &&
        (_suspended || _revivals.isReviving(connection));
  }

  /// Whether the connection behind [key] is neither open nor coming back.
  bool isGone(RelayConnectionKey key) =>
      !isConnectionOpen(key) && !isComingBack(key);

  /// Every connection held to [url].
  List<RelayConnectionKey> keysFor(RelayUrl url) =>
      relays.keys.where((key) => key.url == url).toList();

  /// Waits up to [timeout] for [transport] to open, and returns why it did not.
  static Future<Object?> _whyNotOpen(
    NostrTransport transport,
    Duration timeout,
  ) async {
    if (!transport.isOpen) {
      try {
        await transport.ready.timeout(timeout);
      } catch (error) {
        return error;
      }
    }
    return transport.isOpen ? null : StateError("closed once ready");
  }

  /// Opens the connection behind [key] unless it is open already, and says
  /// what came of it. A bound connection opens bound, or not at all.
  ///
  /// A connection that dropped and is coming back is left to its backoff. One
  /// whose last attempt failed within the `unreachableRelayRetryAfter` of the
  /// constructor is not tried again, unless [retryUnreachable].
  ///
  /// [as] is the signer to open a bound connection with. Without it, the
  /// signer is looked up: that works for a registered account, or for the one
  /// the connection was opened with before.
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
        connection.attempts.failedWithin(_unreachableRelayRetryAfter)) {
      return const NotOpened(
        RelayFailure(
          RelayFailureKind.unreachable,
          "its last attempt failed too recently",
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
    return isComingBack(key) ? const ComingBack() : null;
  }

  /// Opens the connection behind [key] now, whatever its last attempt, and
  /// says why it could not. A connection that is coming back is tried now,
  /// rather than after its backoff. See [ensureOpen] for [as].
  Future<RelayFailure?> connectNow(
    RelayConnectionKey key, {
    NostrSigner? as,
    TimeoutPausable? pausing,
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) {
    if (blockedRelays.contains(key.url)) {
      return Future.value(const RelayFailure(RelayFailureKind.blocked));
    }
    if (_suspended) return Future.value(_suspendedFailure);
    final connection = relays[key];
    if (connection != null && _revivals.isReviving(connection)) {
      return _revivals.hurry(connection);
    }
    return _open(key, as: as, pausing: pausing, connectTimeout: connectTimeout);
  }

  /// Opens the connection behind [key], creating it if it is new, and says why
  /// it could not.
  ///
  /// A bound connection opens with [as], or with the signer it is known by.
  /// Binding it does not authenticate it: it only fixes the one identity the
  /// socket may ever take. A relay sends its challenge when it wants, and some
  /// only do once a request needs it. A new binding is first put to the
  /// `AuthHandler`, with [pausing] paused while it decides.
  Future<RelayFailure?> _open(
    RelayConnectionKey key, {
    NostrSigner? as,
    TimeoutPausable? pausing,
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    if (_disposed) return _disposedFailure;
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
    if (_disposed) return Future.value(_disposedFailure);
    if (_suspended) return Future.value(_suspendedFailure);
    if (blockedRelays.contains(connection.url)) {
      return Future.value(const RelayFailure(RelayFailureKind.blocked));
    }
    if (connection.isConnected) return Future.value();
    return connection.opening ??= _openSocket(
      connection,
      connectTimeout,
    ).whenComplete(() => connection.opening = null);
  }

  /// Opens a new socket for [connection], and says why it could not. A refused
  /// socket is tried again until [connectTimeout] runs out.
  Future<RelayFailure?> _openSocket(
    RelayConnection connection,
    Duration connectTimeout,
  ) async {
    final key = connection.key;
    final url = key.url;
    NostrTransport? transport;
    bool ownsTransport() => _isCurrent(connection, transport);

    connection.attempts.tryingToConnect();
    notifyChanged();
    connection.idleFor.reset();
    _idle.watch();
    logger.info(() => "Connecting to $url");
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
        maximum: _reconnectMaximumDelay,
      );
      while (true) {
        if (_suspended) throw StateError("suspended while connecting");
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
      logger.info(() => "Could not connect to $url: $error");
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
      if (_suspended) {
        // a failure would keep REQs off this relay for a while after resume
        connection.attempts.stoppedConnecting();
        notifyChanged();
        return _suspendedFailure;
      }
      connection.attempts.failedToConnect();
      notifyChanged();
      return RelayFailure(RelayFailureKind.unreachable, "$error");
    }
    logger.info(() => "Connected to $url");
    connection.attempts.succeededToConnect();
    notifyChanged();
    return null;
  }

  /// Waits until the connection behind [key] is back from its drop or given
  /// up, and says whether it is open.
  Future<bool> whenBack(RelayConnectionKey key) async {
    while (true) {
      if (_suspended) {
        await _resumed.future;
        continue;
      }
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

  /// Closes every socket, and opens none until [resume].
  ///
  /// A connection that carries work is kept, without its revival, and is
  /// coming back to whatever asks. One that carries none is forgotten.
  Future<void> suspend() async {
    if (_disposed || _suspended) return;
    _suspended = true;
    _resumed = Completer();
    _idle.stop();
    final closing = <Future<void>>[];
    for (final key in relays.keys.toList()) {
      final connection = relays[key];
      if (connection == null) continue;
      if (!hasWorkOn(key)) {
        closing.add(closeConnection(key));
        continue;
      }
      _revivals.stop(connection);
      closing.add(connection.close());
    }
    notifyChanged();
    await Future.wait(closing);
  }

  /// Ends [suspend]: each connection still kept is brought back on a fresh
  /// backoff, as after a drop. Completes once each one came back or failed
  /// its first attempt.
  Future<void> resume() async {
    if (!_suspended) return;
    _suspended = false;
    final attempts = [
      for (final connection in relays.values.toList())
        if (!connection.isConnected) _revivals.revive(connection),
    ];
    _resumed.complete();
    await Future.wait(attempts);
  }

  /// Reconnects at once every connection that is not connected, even one whose
  /// last attempt just failed, and replays the requests it was carrying.
  Future<void> reconnectClosedConnections() => Future.wait([
    for (final connection in relays.values.toList())
      if (!connection.isConnected) _reconnect(connection),
  ]);

  Future<void> _reconnect(RelayConnection connection) async {
    // a revival tells the listener on its own once it is back
    final revived = _revivals.isReviving(connection);
    if (await connectNow(connection.key) == null && !revived) {
      listener.onBack(connection);
    }
  }

  /// Writes [data], and says whether it reached the transport.
  bool _sendRaw(
    RelayConnection connection,
    NostrTransport transport,
    dynamic data,
  ) {
    if (!identical(connection.relayTransport, transport) || !transport.isOpen) {
      logger.finest(
        () => "Not sent to ${connection.url}: its socket changed or closed",
      );
      return false;
    }
    transport.send(data);
    connection.idleFor.reset();
    logger.fine(() => "Sent to ${connection.url}: $data");
    return true;
  }

  /// Sends [message] on the current socket of [connection] once it is ready.
  ///
  /// Throws when that socket is replaced or closed first. What it still owed
  /// is then replayed on the next one.
  Future<void> sendOrThrow(
    RelayConnection connection,
    List<dynamic> message,
  ) async {
    final transport = connection.relayTransport;
    if (transport == null) {
      throw StateError("relay not connected: ${connection.url}");
    }
    await transport.ready;
    // a REQ already waited for them in its queue
    if (message.first == 'EVENT') {
      await connection.limits.settled;
    }
    if (!identical(connection.relayTransport, transport) || !transport.isOpen) {
      throw StateError(
        "socket replaced or closed before send: ${connection.url}",
      );
    }
    final String encodedMsg = jsonEncode(message);
    final length = utf8Length(encodedMsg);
    _limits.check(connection, length);
    if (_sendRaw(connection, transport, encodedMsg)) {
      connection.limits.longestMessage = max(
        connection.limits.longestMessage,
        length,
      );
      _countRequest(connection, message);
    }
  }

  /// Counts the REQs open on [connection], so its slots follow what was
  /// actually written there.
  void _countRequest(RelayConnection connection, List<dynamic> message) {
    switch (message) {
      case ['REQ', final String id, ...]:
        connection.slots.wrote(id);
      case ['CLOSE', final String id, ...]:
        if (connection.slots.ended(id)) {
          listener.admitQueuedOn(connection);
        }
    }
  }

  /// Sends [message] on the connection behind [key] once its socket is ready,
  /// see [sendTo].
  void send(RelayConnectionKey key, List<dynamic> message) {
    final connection = relays[key];
    if (connection == null) {
      logger.finest(() => "Not sent to $key: no such connection");
      return;
    }
    sendTo(connection, message);
  }

  /// Sends [message] on [connection] once its socket is ready. When that
  /// socket goes away first, the message is dropped and logged.
  void sendTo(RelayConnection connection, List<dynamic> message) {
    unawaited(
      sendOrThrow(connection, message).catchError((Object error) {
        if (error is MessageTooLong) {
          logger.warning(() => "Not sent to ${connection.url}: $error");
        } else {
          logger.finest(() => "Not sent to ${connection.url}: $error");
        }
      }),
    );
  }

  /// Whether [connection] is still the one tracked under its key, running on
  /// [transport]. Whatever a replaced connection or socket reports is stale.
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
        logger.info(() => "Socket error on ${connection.url}: $error");
        _handleTransportGone(connection, transport);
      },
      onDone: () {
        logger.finest(
          () =>
              "Socket of ${connection.url} closed: ${connection.relayTransport?.closeCode} ${connection.relayTransport?.closeReason}",
        );
        _handleTransportGone(connection, transport);
      },
    );
  }

  /// Cleans up after [transport] ended, then brings the connection back, or
  /// forgets it when nothing needs it any more.
  ///
  /// A socket ends here both on an error and on a close: an error cancels the
  /// stream subscription, so no done event follows it. A late event from a
  /// socket that was already replaced leaves the current one alone.
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
    if (transport?.closeCode == ws_status.messageTooBig) {
      _limits.learnFrom(connection);
    }
    // the AUTH the relay accepted died with the socket, and so did any still
    // waiting for its OK
    final retired = connection.close();
    if (!hasWorkOn(key)) {
      logger.info(() => "Lost $key, nothing left on it");
      unawaited(closeConnection(key));
      return;
    }
    notifyChanged();
    // deliberate closes cancel the stream subscription first and never get here
    if (allowReconnect) {
      logger.info(() => "Lost $key, reconnecting");
      _revivals.comeBack(connection, retired);
      return;
    }
    _revivals.stop(connection);
    listener.onGone(key);
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
      listener.onMessage(decodeNostrMsg(message), connection);
    } catch (error, stackTrace) {
      logger.severe(
        () => "Could not handle a message from ${connection.url}: $message",
        error,
        stackTrace,
      );
    }
  }

  /// Closes one connection and forgets it.
  ///
  /// A connection that already lost its socket is forgotten too. Left behind,
  /// it would keep its auth state and reconnect.
  Future<void> closeConnection(RelayConnectionKey key) {
    final connection = relays.remove(key);
    if (connection == null) return Future.value();
    notifyChanged();
    logger.fine(() => "Closing $key");
    _revivals.stop(connection);
    final closing = connection.close();
    listener.onGone(key);
    return closing;
  }

  /// Closes every connection, and [changes], and opens none afterwards.
  Future<void> dispose() async {
    _disposed = true;
    _suspended = false;
    if (!_resumed.isCompleted) _resumed.complete();
    await closeAll();
    await _updates.close();
  }

  /// Closes every connection.
  Future<void> closeAll() async {
    _idle.stop();
    final keys = relays.keys.toList();
    try {
      await Future.wait(keys.map(closeConnection));
    } catch (error, stackTrace) {
      logger.severe(
        () => "Could not close every connection",
        error,
        stackTrace,
      );
    }
  }
}
