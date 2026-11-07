import 'dart:async';
import 'dart:convert';

import 'package:rxdart/rxdart.dart';

import '../config/relay_defaults.dart';
import 'package:ndk_auth/ndk_auth.dart';
import '../domain_layer/entities/timeout_pausable.dart';
import '../domain_layer/entities/relay_connection_key.dart';
import '../domain_layer/entities/relay_failure.dart';
import '../domain_layer/entities/subscription_limit.dart';
import '../domain_layer/repositories/nostr_transport.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:ndk_isolates/ndk_isolates.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'client_msg.dart';
import 'decode_nostr_msg.dart';
import 'nostr_message_raw.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'web_socket_client/web_socket_client.dart';

/// What the work riding on the connections of [RelayConnections] has to do
/// when a socket comes back or goes away.
abstract interface class ConnectionListener {
  /// Puts back on [connectivity] what the socket it replaces still owed.
  void replayOn(RelayConnection connectivity);

  /// Gives up on what was waiting for [key] to replay it after an
  /// authentication.
  void endAuthRetriesOn(RelayConnectionKey key);

  /// Gives up on what [key] still owed, once nothing will bring it back.
  void endRequestsOn(RelayConnectionKey key);

  /// Writes the queued REQs that now fit on [connectivity]: a slot was freed
  /// there, or its limit became known.
  void admitQueuedOn(RelayConnection connectivity);
}

/// A decoded relay message, in the order its relay sent it.
typedef RelayMessageHandler =
    Future<void> Function(
      NostrMessageRaw message,
      RelayConnection connectivity,
      dynamic raw,
    );

/// A connection whose socket dropped, while it is being brought back.
class _Revival {
  final RelayConnection connectivity;
  final Backoff backoff;
  final Stopwatch since = Stopwatch()..start();
  Timer? next;
  Future<bool>? attempt;

  _Revival(this.connectivity, int maximumStep)
    : backoff = BinaryExponentialBackoff(
        initial: RECONNECT_INITIAL_DELAY,
        maximumStep: maximumStep,
      );
}

/// The connections of a `RelayManager`: opening, reconnecting and closing them,
/// writing to them and reading from them. Internal to ndk_core.
///
/// It is the only thing that reconnects: a transport is a single socket.
class RelayConnections {
  final NostrTransportFactory nostrTransportFactory;
  final RelayAuth _auth;
  final RelayMessageHandler _onMessage;
  final int _reconnectMaximumStep;
  final SubscriptionLimit? _subscriptionLimit;

  /// told when a socket comes back or goes away, set before any connection
  late final ConnectionListener listener;

  /// Are reconnects allowed when a connection drops?
  bool allowReconnect;

  /// touched relays - connected, connecting, disconnected
  /// key: relay url and identity bound to the connection
  /// value: relay connectivity
  final Map<RelayConnectionKey, RelayConnection> relays = {};

  /// clean urls of relays that are blocked
  final Set<String> blockedRelays = {};

  /// Tracks relay connect attempts that are still finishing setup so callers
  /// can wait for "socket open + listener attached", not just raw socket open.
  final Map<
    RelayConnectionKey,
    Completer<({bool connected, RelayFailure? failure})>
  >
  _connectReadyCompleters = {};

  final Map<String, Set<Completer<void>>> _requestSentWaiters = {};

  // Track processing order per relay so EVENT/EOSE/AUTH/CLOSED ordering stays
  // correct without introducing cross-relay head-of-line blocking.
  final Map<String, Completer<void>> _lastMessageCompleters = {};

  final _updates = BehaviorSubject<List<RelayConnection>>();

  final Map<RelayConnectionKey, _Revival> _revivals = {};

  RelayConnections({
    required this.nostrTransportFactory,
    required RelayAuth auth,
    required RelayMessageHandler onMessage,
    this.allowReconnect = true,
    int reconnectMaximumStep = DEFAULT_RECONNECT_MAXIMUM_STEP,
    SubscriptionLimit? subscriptionLimit,
  }) : _auth = auth,
       _onMessage = onMessage,
       _reconnectMaximumStep = reconnectMaximumStep,
       _subscriptionLimit = subscriptionLimit;

  /// every connection on each change, the latest one cached
  Stream<List<RelayConnection>> get changes => _updates.stream;

  void notifyChanged() {
    _updates.add(relays.values.toList());
  }

  /// Every open connection, anonymous or bound, so a relay can show up more
  /// than once. [isRelayConnected] checks a single relay.
  List<RelayConnection> get connectedRelays =>
      relays.values.where((connectivity) => connectivity.isConnected).toList();

  /// Connected connections bound to nobody, one per relay at most.
  ///
  /// Engines pick relays, not identities: sending on every connection of a
  /// relay would duplicate the request, and sending on a bound one would make
  /// it attributable. An identity is added later, by the re-route, and only on
  /// the relays that ask for one.
  List<RelayConnection> get connectedAnonymousRelays => relays.values
      .where((connectivity) => connectivity.key.isAnonymous)
      .where((connectivity) => connectivity.isConnected)
      .toList();

  /// Whether the anonymous connection to [url] is open.
  bool isRelayConnected(String url) =>
      isConnectionOpen(RelayConnectionKey.anonymous(url));

  /// checks if the connection identified by [key] is open
  bool isConnectionOpen(RelayConnectionKey key) =>
      relays[key]?.relayTransport?.isOpen() ?? false;

  /// checks if the connection identified by [key] is connecting
  bool isConnectionConnecting(RelayConnectionKey key) {
    final relay = relays[key]?.relay;
    return relay != null && relay.connecting;
  }

  /// Whether a socket for [key] is still being opened.
  bool isOpening(RelayConnectionKey key) {
    final connectivity = relays[key];
    return _connectReadyCompleters.containsKey(key) ||
        (connectivity?.relay.connecting ?? false) ||
        (connectivity?.relayTransport?.isConnecting() ?? false);
  }

  /// The anonymous connection to [url], if there is one.
  RelayConnection? getRelayConnectivity(String url) =>
      relays[RelayConnectionKey.anonymous(url)];

  /// every connection currently held towards [url]
  List<RelayConnectionKey> keysFor(String url) {
    final relayUrl = RelayConnectionKey.anonymous(url).url;
    return relays.keys.where((key) => key.url == relayUrl).toList();
  }

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
  Future<({bool connected, RelayFailure? failure})> connectRelay({
    required String dirtyUrl,
    String? authPubkey,
    Duration connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
  }) async {
    String? url = cleanRelayUrl(dirtyUrl);
    if (url == null) {
      notifyChanged();
      return (
        connected: false,
        failure: const RelayFailure(RelayFailureKind.invalidUrl),
      );
    }
    if (blockedRelays.contains(url)) {
      notifyChanged();
      return (
        connected: false,
        failure: const RelayFailure(RelayFailureKind.blocked),
      );
    }

    final connectionKey = authPubkey == null
        ? RelayConnectionKey.anonymous(url)
        : RelayConnectionKey.authenticated(url, authPubkey);

    if (isConnectionOpen(connectionKey)) {
      Logger.log.t(() => "relay already connected: $connectionKey");
      notifyChanged();
      return (connected: true, failure: null);
    }

    if (isConnectionConnecting(connectionKey) ||
        _connectReadyCompleters.containsKey(connectionKey)) {
      Logger.log.t(() => "relay is already connecting: $connectionKey");
      final inFlightConnect = _connectReadyCompleters[connectionKey];
      if (inFlightConnect != null) {
        final result = await inFlightConnect.future;
        notifyChanged();
        return result;
      }
      notifyChanged();
      return (
        connected: false,
        failure: const RelayFailure(RelayFailureKind.stillConnecting),
      );
    }
    RelayConnection? relayConnectivity = relays[connectionKey];
    final connectCompleter =
        Completer<({bool connected, RelayFailure? failure})>();
    _connectReadyCompleters[connectionKey] = connectCompleter;
    NostrTransport? transport;
    bool ownsTransport() => _isCurrent(relayConnectivity, transport);
    Object? failure;

    try {
      if (relayConnectivity == null) {
        relayConnectivity = RelayConnection(connectionKey);
        relays[connectionKey] = relayConnectivity;
      }

      relayConnectivity.relay.tryingToConnect();

      Logger.log.i(() => "connecting to relay $dirtyUrl");

      // a fresh socket for a key we may already know: nothing the previous one
      // authenticated carries over
      _auth.forget(connectionKey);
      // A disconnected transport may still own reconnect timers and listeners.
      // Retire it before replacement or it can later open an untracked socket.
      await relayConnectivity.close();
      if (!identical(relays[connectionKey], relayConnectivity)) {
        throw StateError(
          'Connection was removed while replacing its transport',
        );
      }
      _askSubscriptionLimit(relayConnectivity);
      final elapsed = Stopwatch()..start();
      final backoff = BinaryExponentialBackoff(
        initial: RECONNECT_INITIAL_DELAY,
        maximumStep: _reconnectMaximumStep,
      );
      while (true) {
        transport = nostrTransportFactory(url);
        relayConnectivity.relayTransport = transport;
        // Start listening immediately so we don't miss early frames such as
        // relay AUTH challenges that may arrive before the transport reports
        // itself fully open.
        _startListeningToSocket(relayConnectivity);
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
        await relayConnectivity.close();
        await Future<void>.delayed(wait);
        if (!identical(relays[connectionKey], relayConnectivity)) {
          throw StateError('Connection was removed while connecting');
        }
      }

      Logger.log.i(() => "connected to relay: $url");
      relayConnectivity.relay.succeededToConnect();
      relayConnectivity.stats.connections++;
      final connected = (connected: true, failure: null);
      if (!connectCompleter.isCompleted) {
        connectCompleter.complete(connected);
      }
      if (identical(_connectReadyCompleters[connectionKey], connectCompleter)) {
        _connectReadyCompleters.remove(connectionKey);
      }
      notifyChanged();
      // opened by someone else while waiting for its next attempt: replay now
      if (_revivals[connectionKey]?.attempt == null &&
          _revivals.containsKey(connectionKey)) {
        unawaited(_revive(relayConnectivity));
      }
      return connected;
    } catch (e) {
      failure = e;
      Logger.log.e(() => "!! could not connect to $url -> $failure");
      try {
        if (transport == null ||
            identical(relayConnectivity!.relayTransport, transport)) {
          await relayConnectivity!.close();
        } else {
          await transport.close();
        }
      } catch (closeError) {
        Logger.log.w(() => "Error retiring transport for $url: $closeError");
      }
    }
    final failedConnectivity = relayConnectivity;
    if (failedConnectivity != null) {
      failedConnectivity.relay.failedToConnect();
      failedConnectivity.stats.connectionErrors++;
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

  /// Asks the [SubscriptionLimit] for the socket [connectivity] is about to
  /// open. Its REQs wait in their queue until it answers, or until
  /// [SUBSCRIPTION_LIMIT_TIMEOUT] gives them the default.
  void _askSubscriptionLimit(RelayConnection connectivity) {
    final generation = ++connectivity.subscriptionLimitGeneration;
    connectivity.subscriptionLimit = null;
    final provider = _subscriptionLimit;
    if (provider == null) {
      _setSubscriptionLimit(connectivity, generation, null);
      return;
    }
    FutureOr<int?> answer;
    try {
      answer = provider(connectivity.url);
    } catch (error) {
      Logger.log.w(
        () => "No subscription limit for ${connectivity.url}",
        error: error,
      );
      answer = null;
    }
    if (answer is! Future<int?>) {
      _setSubscriptionLimit(connectivity, generation, answer);
      return;
    }
    answer
        .timeout(SUBSCRIPTION_LIMIT_TIMEOUT)
        .then(
          (limit) => _setSubscriptionLimit(connectivity, generation, limit),
          onError: (Object error) {
            Logger.log.w(
              () => "No subscription limit for ${connectivity.url}",
              error: error,
            );
            _setSubscriptionLimit(connectivity, generation, null);
          },
        );
  }

  void _setSubscriptionLimit(
    RelayConnection connectivity,
    int generation,
    int? limit,
  ) {
    if (connectivity.subscriptionLimitGeneration != generation) return;
    connectivity.subscriptionLimit = limit != null && limit > 0
        ? limit
        : DEFAULT_MAX_SUBSCRIPTIONS_PER_CONNECTION;
    listener.admitQueuedOn(connectivity);
  }

  /// Reconnects the anonymous connection to a relay, if it is closed.
  Future<bool> reconnectRelay(String url, {bool force = false}) =>
      reconnectConnection(RelayConnectionKey.anonymous(url), force: force);

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
  }) async {
    final inFlightConnect = _connectReadyCompleters[key];
    if (inFlightConnect != null) {
      final connected = (await inFlightConnect.future).connected;
      notifyChanged();
      return connected;
    }

    RelayConnection? relayConnectivity = relays[key];
    final transport = relayConnectivity?.relayTransport;
    if (transport != null &&
        await _whyNotOpen(transport, DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT) ==
            null &&
        identical(relayConnectivity!.relayTransport, transport)) {
      notifyChanged();
      return true;
    }
    if (relayConnectivity == null ||
        relayConnectivity.relayTransport == null ||
        !relayConnectivity.relayTransport!.isOpen()) {
      if (!force &&
          (relayConnectivity != null &&
              !relayConnectivity.relay.wasLastConnectTryLongerThanSeconds(
                FAIL_RELAY_CONNECT_TRY_AFTER_SECONDS,
              ))) {
        // don't try too often
        notifyChanged();
        return false;
      }

      if (!key.isAnonymous) {
        final account = as ?? _auth.accountFor(key);
        if (account == null) {
          Logger.log.w(() => "No account left to reconnect $key");
          return false;
        }
        return await openConnectionAs(key.url, account, pausing: pausing) !=
            null;
      }

      if (!(await connectRelay(dirtyUrl: key.url)).connected) {
        // could not connect
        return false;
      }
      relayConnectivity = relays[key];
      if (relayConnectivity == null ||
          relayConnectivity.relayTransport == null ||
          !relayConnectivity.relayTransport!.isOpen()) {
        // web socket is not open
        return false;
      }
    }
    return true;
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
    String url,
    Account account, {
    Duration connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
    TimeoutPausable? pausing,
  }) async {
    if (!account.signer.canSign()) {
      Logger.log.w(() => "Cannot bind a connection to ${account.pubkey}");
      return null;
    }
    final key = RelayConnectionKey.authenticated(url, account.pubkey);
    if (relays[key] == null && !await _auth.consent(key, pausing: pausing)) {
      Logger.log.d(() => "Not allowed to open $key");
      return null;
    }
    _auth.bind(key, account);

    if (isConnectionOpen(key)) {
      return relays[key];
    }

    final result = await connectRelay(
      dirtyUrl: url,
      authPubkey: account.pubkey,
      connectTimeout: connectTimeout,
    );
    final connectivity = relays[key];
    if (!result.connected || connectivity == null) {
      Logger.log.w(() => "Could not open $key: ${result.failure}");
      return null;
    }
    return connectivity;
  }

  /// Answers the challenge for [key] and completes once the relay accepted the
  /// AUTH event. Concurrent callers share a single AUTH.
  Future<bool> authenticate(RelayConnectionKey key) {
    final connectivity = relays[key];
    if (key.isAnonymous || connectivity == null) {
      return Future.value(false);
    }
    return _auth.authenticate(key, (message) => sendTo(connectivity, message));
  }

  /// Closes and clears only transport-scoped state of one connection, while
  /// keeping its entry and relay-scoped metadata in memory.
  Future<void> resetConnection(RelayConnectionKey key) async {
    final connectivity = relays[key];
    if (connectivity != null) {
      Logger.log.d(() => "Resetting transport for $key...");
      _stopReviving(key);
      connectivity.relay.failedToConnect();
      _auth.forget(key);
      await connectivity.close();
      listener.endAuthRetriesOn(key);
      notifyChanged();
    }
  }

  /// Reconnects every connection that is not connected, all at once, even one
  /// that just failed to, and replays the requests it was carrying.
  Future<void> reconnectClosedConnections() => Future.wait([
    for (final connectivity in relays.values.toList())
      if (!connectivity.isConnected) _reconnectNow(connectivity),
  ]);

  Future<void> _reconnectNow(RelayConnection connectivity) async {
    if (_revivals.containsKey(connectivity.key)) {
      await _revive(connectivity);
      return;
    }
    final connected = await reconnectConnection(connectivity.key, force: true);
    notifyChanged();
    if (connected) listener.replayOn(connectivity);
  }

  /// Brings [connectivity] back after its socket dropped: one attempt now, then
  /// one after each wait of its backoff, until it is back or given up.
  Future<bool> _revive(RelayConnection connectivity) {
    final key = connectivity.key;
    var revival = _revivals[key];
    if (revival == null || !identical(revival.connectivity, connectivity)) {
      revival = _revivals[key] = _Revival(connectivity, _reconnectMaximumStep);
    }
    revival.next?.cancel();
    final current = revival;
    return revival.attempt ??= _attemptRevival(
      revival,
    ).whenComplete(() => current.attempt = null);
  }

  Future<bool> _attemptRevival(_Revival revival) async {
    final connectivity = revival.connectivity;
    final key = connectivity.key;
    final connected = await reconnectConnection(key, force: true).catchError((
      Object error,
    ) {
      Logger.log.e(() => "Could not reconnect $key", error: error);
      return false;
    });
    // closed or reset meanwhile, which settled what it carried
    if (!identical(_revivals[key], revival)) return connected;
    notifyChanged();
    if (connected) {
      _revivals.remove(key);
      listener.replayOn(connectivity);
      listener.endAuthRetriesOn(key);
      return true;
    }
    if (!allowReconnect || revival.since.elapsed >= RECONNECT_GIVE_UP_AFTER) {
      _revivals.remove(key);
      listener.endAuthRetriesOn(key);
      listener.endRequestsOn(key);
      return false;
    }
    revival.next = Timer(revival.backoff.next(), () => _revive(connectivity));
    return false;
  }

  void _stopReviving(RelayConnectionKey key) =>
      _revivals.remove(key)?.next?.cancel();

  /// Writes [data] and tells whether it reached the transport
  bool _sendRaw(
    RelayConnection relayConnectivity,
    NostrTransport transport,
    dynamic data,
  ) {
    if (!identical(relayConnectivity.relayTransport, transport) ||
        !transport.isOpen()) {
      Logger.log.t(
        () =>
            "skip send to ${relayConnectivity.url}: transport changed or closed",
      );
      return false;
    }
    transport.send(data);
    Logger.log.d(() => "send message to ${relayConnectivity.url}: $data");
    return true;
  }

  /// Sends [message] and surfaces transport churn/closed-socket failures to
  /// the caller instead of silently dropping the write.
  Future<void> sendOrThrow(
    RelayConnection relayConnectivity,
    List<dynamic> message,
  ) async {
    NostrTransport? transport = relayConnectivity.relayTransport;
    if (transport == null) {
      throw StateError("relay not connected: ${relayConnectivity.url}");
    }

    await transport.ready;

    if (!identical(relayConnectivity.relayTransport, transport) ||
        !transport.isOpen()) {
      transport = relayConnectivity.relayTransport;
      if (transport == null) {
        throw StateError(
          "transport changed while waiting for ${relayConnectivity.url}",
        );
      }

      await transport.ready;

      if (!identical(relayConnectivity.relayTransport, transport) ||
          !transport.isOpen()) {
        throw StateError(
          "transport changed while waiting for ${relayConnectivity.url}",
        );
      }
    }

    final String encodedMsg = jsonEncode(message);
    if (!identical(relayConnectivity.relayTransport, transport) ||
        !transport.isOpen()) {
      throw StateError(
        "transport closed before send: ${relayConnectivity.url}",
      );
    }
    if (_sendRaw(relayConnectivity, transport, encodedMsg)) {
      _countRequest(relayConnectivity, message);
    }
  }

  /// Keeps the open requests of a connection on the connection that carries
  /// them: a REQ re-routed to another one is not accounted here.
  void _countRequest(RelayConnection relayConnectivity, List<dynamic> message) {
    switch (message) {
      case [ClientMsgType.kReq, final String id, ...]:
        relayConnectivity.stats.openRequestIds.add(id);
        for (final waiter
            in _requestSentWaiters.remove(id) ?? <Completer<void>>{}) {
          waiter.complete();
        }
      case [ClientMsgType.kClose, final String id, ...]:
        if (relayConnectivity.stats.openRequestIds.remove(id)) {
          listener.admitQueuedOn(relayConnectivity);
        }
    }
  }

  /// Waits until a REQ with [id] is sent on a connected relay.
  Future<void> waitForRequestSent(String id, Duration timeout) async {
    if (relays.values.any(
      (relay) => relay.isConnected && relay.stats.openRequestIds.contains(id),
    )) {
      return;
    }
    final waiter = Completer<void>();
    _requestSentWaiters.putIfAbsent(id, () => {}).add(waiter);
    try {
      await waiter.future.timeout(
        timeout,
        onTimeout: () =>
            throw TimeoutException('REQ $id was not sent', timeout),
      );
    } finally {
      final waiters = _requestSentWaiters[id];
      waiters?.remove(waiter);
      if (waiters != null && waiters.isEmpty) _requestSentWaiters.remove(id);
    }
  }

  /// Sends [message] on the connection behind [key] once its socket is ready,
  /// see [sendTo].
  void send(RelayConnectionKey key, List<dynamic> message) {
    final relayConnectivity = relays[key];
    if (relayConnectivity == null) {
      Logger.log.t(() => "skip send to $key: no such connection");
      return;
    }
    sendTo(relayConnectivity, message);
  }

  /// Sends [message] on [relayConnectivity] once its socket is ready. It is
  /// dropped, and logged, when that socket goes away first.
  void sendTo(RelayConnection relayConnectivity, List<dynamic> message) {
    unawaited(
      sendOrThrow(relayConnectivity, message).catchError((Object error) {
        Logger.log.t(() => "skip send to ${relayConnectivity.url}: $error");
      }),
    );
  }

  /// Whether [connectivity] is still the connection tracked under its key, and
  /// [transport] still the one it runs on: anything a replaced one reports is
  /// stale.
  bool _isCurrent(RelayConnection? connectivity, NostrTransport? transport) =>
      connectivity != null &&
      transport != null &&
      identical(relays[connectivity.key], connectivity) &&
      identical(connectivity.relayTransport, transport);

  void _startListeningToSocket(RelayConnection relayConnectivity) {
    final transport = relayConnectivity.relayTransport;
    relayConnectivity.listen(
      (message) {
        if (!_isCurrent(relayConnectivity, transport)) return;
        _handleIncomingMessage(message, relayConnectivity);
      },
      onError: (error) {
        if (!_isCurrent(relayConnectivity, transport)) return;
        Logger.log.e(() => "onError ${relayConnectivity.url} on listen $error");
        _handleTransportGone(relayConnectivity, transport);
      },
      onDone: () {
        Logger.log.t(
          () =>
              "onDone ${relayConnectivity.url} on listen (close: ${relayConnectivity.relayTransport?.closeCode()} ${relayConnectivity.relayTransport?.closeReason()})",
        );
        _handleTransportGone(relayConnectivity, transport);
      },
    );
  }

  /// Cleans up after [transport] died and brings the connection back. Both ways
  /// a socket can end land here: an error cancels the stream subscription, so
  /// the done event that would otherwise follow never arrives.
  ///
  /// Runs once per transport, so a late event from a socket that was already
  /// replaced leaves the current one alone.
  Future<void> _handleTransportGone(
    RelayConnection relayConnectivity,
    NostrTransport? transport,
  ) async {
    if (!_isCurrent(relayConnectivity, transport)) return;
    final key = relayConnectivity.key;
    // a socket that ends while it opens is a failed connect, which connectRelay
    // reports and the backoff retries: reviving it here would skip that wait
    if (_connectReadyCompleters.containsKey(key)) return;
    relayConnectivity.stats.connectionErrors++;
    // the AUTH the relay accepted died with the socket, and so did any still
    // waiting for its OK
    _auth.forget(key);

    try {
      await relayConnectivity.close();
    } catch (e) {
      Logger.log.w(() => "Error closing relay ${relayConnectivity.url}: $e");
    }
    // Closing can yield while a new owner or transport takes over. Its AUTH
    // and subscriptions belong to the replacement, not this retired socket.
    if (!identical(relays[key], relayConnectivity) ||
        relayConnectivity.relayTransport != null) {
      return;
    }
    notifyChanged();
    // deliberate closes cancel the stream subscription first and never get here
    if (allowReconnect) {
      Logger.log.i(() => "closed ${relayConnectivity.url}. Reconnecting");
      unawaited(_revive(relayConnectivity));
      return;
    }
    listener.endAuthRetriesOn(key);
    listener.endRequestsOn(key);
  }

  Future<void> _handleIncomingMessage(
    dynamic message,
    RelayConnection relayConnectivity,
  ) async {
    final relayUrl = relayConnectivity.url;
    final previousMessage = _lastMessageCompleters[relayUrl];

    final myCompleter = Completer<void>();
    _lastMessageCompleters[relayUrl] = myCompleter;

    NostrMessageRaw? nostrMsg;
    if (message is String) {
      try {
        nostrMsg = await IsolateManager.instance
            .runInEncodingIsolate<String, NostrMessageRaw>(
              decodeNostrMsg,
              message,
            );
      } catch (e) {
        // Isolates not available on web
        nostrMsg = decodeNostrMsg(message);
      }
    }

    // a relay controls what it sends: nothing it sends may throw out of here,
    // where it would kill a process that has no zone to catch it
    try {
      await previousMessage?.future;
      if (nostrMsg == null) {
        Logger.log.w(() => "Ignoring a non-text frame from $relayUrl");
        return;
      }
      await _onMessage(nostrMsg, relayConnectivity, message);
    } catch (error, stackTrace) {
      Logger.log.e(
        () => "Could not handle a message from $relayUrl: $message",
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (!myCompleter.isCompleted) {
        myCompleter.complete();
      }
      if (identical(_lastMessageCompleters[relayUrl], myCompleter)) {
        _lastMessageCompleters.remove(relayUrl);
      }
    }
  }

  /// Closes one connection and forgets it. An entry that lost its transport, to
  /// a reset or to a failed connection attempt, is forgotten just the same:
  /// leaving it behind keeps its auth state alive and makes it reconnect.
  Future<void> closeConnection(RelayConnectionKey key) async {
    final connectivity = relays.remove(key);
    if (connectivity == null) {
      return;
    }
    Logger.log.d(() => "Disconnecting $key...");
    _stopReviving(key);
    _auth.unbind(key);
    _auth.forget(key);
    listener.endAuthRetriesOn(key);
    listener.endRequestsOn(key);
    return connectivity.close();
  }

  /// Closes all transports
  Future<void> closeAll() async {
    final keys = relays.keys.toList();
    try {
      await Future.wait(keys.map(closeConnection));
    } catch (e) {
      Logger.log.e(() => e);
    }
  }
}
