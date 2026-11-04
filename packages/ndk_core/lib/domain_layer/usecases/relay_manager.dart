import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:rxdart/rxdart.dart';

import '../../config/broadcast_defaults.dart';
import '../../config/relay_defaults.dart';
import '../../config/request_defaults.dart';
import '../../shared/decode_nostr_msg/decode_nostr_msg.dart';
import '../../shared/helpers/relay_helper.dart';
import '../../shared/isolates/isolate_manager.dart';
import '../../shared/logger/logger.dart';
import '../../shared/nips/nip01/client_msg.dart';
import '../../shared/nips/nip01/helpers.dart';
import '../../src/broadcast_state.dart';
import '../../src/global_state.dart';
import '../../src/request_state.dart';
import '../entities/account.dart';
import '../entities/auth_handler.dart';
import '../entities/broadcast_response.dart';
import '../entities/broadcast_state.dart';
import '../entities/filter.dart';
import '../entities/nip_01_event.dart';
import '../entities/nostr_message_raw.dart';
import '../entities/relay.dart';
import '../entities/auth_policy.dart';
import '../entities/relay_connection_key.dart';
import '../entities/relay_connectivity.dart';
import '../entities/relay_protocol_handler.dart';
import '../entities/relay_request_outcome.dart';
import '../repositories/auth_accounts.dart';
import '../repositories/event_verifier.dart';
import '../repositories/nostr_transport.dart';
import 'nip42/auth_event.dart';
import 'requests/verified_event_cache.dart';
import 'requests/verify_event_stream.dart';

part 'nip42/auth_session.dart';
part 'relay_reqs/relay_publish.dart';
part 'relay_reqs/relay_reqs.dart';

///  relay manager, responsible for lifecycle of relays, sending messages, \
///  and help with tracking of requests
class RelayManager {
  final Completer<void> _seedRelaysCompleter = Completer<void>();
  final Map<String, Set<Completer<void>>> _requestSentWaiters = {};

  /// completes when all seed relays are connected
  Future<void> get seedRelaysConnected => _seedRelaysCompleter.future;

  final GlobalState _globalState = GlobalState();

  /// signer for nip-42 AUTH challenges from relays
  final AuthAccounts? _accounts;

  /// NIP-42 on the current socket of each connection, see [_forgetAuthState]
  final Map<RelayConnectionKey, _AuthSession> _authSessions = {};

  /// the account a connection was opened as, for identities the caller handed
  /// over instead of registering. A challenge can arrive long after whatever
  /// asked for that identity is gone, so the connection has to keep it
  final Map<RelayConnectionKey, Account> _boundAccounts = {};

  /// Tracks relay connect attempts that are still finishing setup so callers
  /// can wait for "socket open + listener attached", not just raw socket open.
  final Map<RelayConnectionKey, Completer<({bool connected, String error})>>
  _connectReadyCompleters = {};

  /// timeout for AUTH callbacks (how long to wait for AUTH OK)
  final Duration authCallbackTimeout;

  /// how long to wait for a NIP-42 challenge once authentication was asked for
  final Duration authChallengeTimeout;

  /// asked before a connection bound to an identity is opened, see [AuthHandler]
  final AuthHandler? authHandler;

  /// in flight [authHandler] questions, so concurrent openings ask once
  final Map<RelayConnectionKey, Future<bool>> _consents = {};

  final List<RelayProtocolHandler> _protocolHandlers = [];

  /// the [RelayReq]s open on this manager, by id, whatever [RelayReqs] opened
  /// them
  final Map<String, RelayReq> _openReqs = {};

  /// nostr transport factory, to create new transports (usually websocket)
  final NostrTransportFactory nostrTransportFactory;

  /// Are reconnects allowed when a connection drops?
  bool allowReconnectRelays = true;

  /// stream controller for relay updates
  final _relayUpdatesStreamController =
      BehaviorSubject<List<RelayConnectivity>>();

  /// stream of connection updates, used to notify connectivity changes, latest
  /// value is cached. A relay can hold several connections, so this cannot be
  /// indexed by url; group by [RelayConnectivity.url] if you need to.
  Stream<List<RelayConnectivity>> get relayConnectivityChanges =>
      _relayUpdatesStreamController.stream;

  /// Every connection this manager holds, connected or not, by key.
  Map<RelayConnectionKey, RelayConnectivity> get connectivities =>
      UnmodifiableMapView(_globalState.relays);

  /// Clean urls of the relays this manager does not connect to.
  Set<String> get blockedRelays => _globalState.blockedRelays;

  /// Whether a broadcast of [eventId] is still waiting on its relays.
  bool isBroadcasting(String eventId) =>
      _globalState.inFlightBroadcasts.containsKey(eventId);

  /// Creates a new relay manager.
  RelayManager({
    required this.nostrTransportFactory,
    AuthAccounts? accounts,
    List<String> bootstrapRelays = const [],
    allowReconnect = true,
    this.authCallbackTimeout = RequestDefaults.DEFAULT_AUTH_CALLBACK_TIMEOUT,
    this.authChallengeTimeout = RequestDefaults.DEFAULT_AUTH_CHALLENGE_TIMEOUT,
    this.authHandler,
  }) : _accounts = accounts {
    bindRelayManagerState(this, _globalState);
    allowReconnectRelays = allowReconnect;
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

  void _updateRelayConnectivity() {
    _relayUpdatesStreamController.add(_globalState.relays.values.toList());
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

  /// Returns a list of fully connected relays, excluding connecting ones.
  /// DO NOT USE THIS FOR CHECKING A SINGLE RELAY, use [isRelayConnected] INSTEAD
  List<RelayConnectivity> get connectedRelays => _globalState.relays.values
      .where((connectivity) => connectivity.isConnected)
      .toList();

  /// Connected connections bound to nobody, one per relay at most.
  ///
  /// Engines pick relays, not identities: sending on every connection of a
  /// relay would duplicate the request, and sending on a bound one would make
  /// it attributable. An identity is added later, by the re-route, and only on
  /// the relays that ask for one.
  List<RelayConnectivity> get connectedAnonymousRelays => _globalState
      .relays
      .values
      .where((connectivity) => connectivity.key.isAnonymous)
      .where((connectivity) => connectivity.isConnected)
      .toList();

  /// checks if a relay is connected, avoid using this
  bool isRelayConnected(String url) =>
      isConnectionOpen(RelayConnectionKey.anonymous(url));

  /// checks if a relay is connecting
  bool isRelayConnecting(String url) =>
      isConnectionConnecting(RelayConnectionKey.anonymous(url));

  /// checks if the connection identified by [key] is open
  bool isConnectionOpen(RelayConnectionKey key) =>
      _globalState.relays[key]?.relayTransport?.isOpen() ?? false;

  /// checks if the connection identified by [key] is connecting
  bool isConnectionConnecting(RelayConnectionKey key) {
    final relay = _globalState.relays[key]?.relay;
    return relay != null && relay.connecting;
  }

  Future<bool> _waitForTransportOpen(
    NostrTransport transport, {
    required int timeoutSeconds,
    bool Function()? stillOwned,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

    while (DateTime.now().isBefore(deadline)) {
      if (stillOwned?.call() == false) return false;
      if (transport.isOpen()) {
        return true;
      }

      try {
        await transport.ready.timeout(const Duration(milliseconds: 250));
      } catch (_) {
        // keep polling isOpen() until the overall timeout expires
      }

      if (stillOwned?.call() == false) return false;
      if (transport.isOpen()) {
        return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    return transport.isOpen();
  }

  /// Connects to a relay to the relay pool.
  /// Returns whether it is connected, and the error message if it is not.
  Future<({bool connected, String error})> connectRelay({
    required String dirtyUrl,
    String? authPubkey,
    int connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
  }) async {
    String? url = cleanRelayUrl(dirtyUrl);
    if (url == null) {
      _updateRelayConnectivity();
      return (connected: false, error: "unclean url");
    }
    if (_globalState.blockedRelays.contains(url)) {
      _updateRelayConnectivity();
      return (connected: false, error: "relay is blocked");
    }

    final connectionKey = authPubkey == null
        ? RelayConnectionKey.anonymous(url)
        : RelayConnectionKey.authenticated(url, authPubkey);

    if (isConnectionOpen(connectionKey)) {
      Logger.log.t(() => "relay already connected: $connectionKey");
      _updateRelayConnectivity();
      return (connected: true, error: "");
    }

    if (isConnectionConnecting(connectionKey) ||
        _connectReadyCompleters.containsKey(connectionKey)) {
      Logger.log.t(() => "relay is already connecting: $connectionKey");
      final inFlightConnect = _connectReadyCompleters[connectionKey];
      if (inFlightConnect != null) {
        final result = await inFlightConnect.future;
        _updateRelayConnectivity();
        return result;
      }
      _updateRelayConnectivity();
      return (connected: false, error: "relay is still connecting");
    }
    RelayConnectivity? relayConnectivity = _globalState.relays[connectionKey];
    final connectCompleter = Completer<({bool connected, String error})>();
    _connectReadyCompleters[connectionKey] = connectCompleter;
    NostrTransport? transport;
    bool ownsTransport() => _isCurrent(relayConnectivity, transport);
    // the transport retries a failed connect on its own and only reports why
    // through onDisconnect, so this is what tells a refusal from a timeout
    Object? transportError;
    Object? failure;

    try {
      if (relayConnectivity == null) {
        relayConnectivity = RelayConnectivity(
          key: connectionKey,
          relay: Relay(url: url),
        );
        _globalState.relays[connectionKey] = relayConnectivity;
      }

      relayConnectivity.relay.tryingToConnect();

      Logger.log.i(() => "connecting to relay $dirtyUrl");

      // a fresh socket for a key we may already know: nothing the previous one
      // authenticated carries over
      _forgetAuthState(connectionKey);
      // A disconnected transport may still own reconnect timers and listeners.
      // Retire it before replacement or it can later open an untracked socket.
      await relayConnectivity.close();
      if (!identical(_globalState.relays[connectionKey], relayConnectivity)) {
        throw StateError(
          'Connection was removed while replacing its transport',
        );
      }
      transport = nostrTransportFactory(
        url,
        onReconnect: () {
          if (!ownsTransport()) return;
          // the relay accepted our AUTH on the socket that just died, not on
          // this one; the binding survives, the authentication does not
          _forgetAuthState(connectionKey);
          _reSubscribeInFlightSubscriptions(relayConnectivity!);
          _updateRelayConnectivity();
        },
        onDisconnect: (code, error, reason) {
          if (!ownsTransport()) return;
          transportError = error ?? transportError;
          relayConnectivity!.stats.connectionErrors++;
          // the transport reconnects under us and keeps its message stream
          // open, so this is the only notice we get that the socket the relay
          // authenticated died
          _forgetAuthState(connectionKey);
          // the requests died with that socket too; onReconnect replays them
          relayConnectivity.stats.openRequestIds.clear();
          _updateRelayConnectivity();
        },
      );
      relayConnectivity.relayTransport = transport;
      // Start listening immediately so we don't miss early frames such as
      // relay AUTH challenges that may arrive before the transport reports
      // itself fully open.
      _startListeningToSocket(relayConnectivity);
      final opened = await _waitForTransportOpen(
        transport,
        timeoutSeconds: connectTimeout,
        stillOwned: ownsTransport,
      );
      if (!opened || !ownsTransport()) {
        throw TimeoutException(
          "Future not completed",
          Duration(seconds: connectTimeout),
        );
      }

      Logger.log.i(() => "connected to relay: $url");
      relayConnectivity.relay.succeededToConnect();
      relayConnectivity.stats.connections++;
      final connected = (connected: true, error: "");
      if (!connectCompleter.isCompleted) {
        connectCompleter.complete(connected);
      }
      if (identical(_connectReadyCompleters[connectionKey], connectCompleter)) {
        _connectReadyCompleters.remove(connectionKey);
      }
      _updateRelayConnectivity();
      return connected;
    } catch (e) {
      failure = transportError ?? e;
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
      error: "could not connect to $url: $failure",
    );
    if (!connectCompleter.isCompleted) {
      connectCompleter.complete(failed);
    }
    if (identical(_connectReadyCompleters[connectionKey], connectCompleter)) {
      _connectReadyCompleters.remove(connectionKey);
    }
    _updateRelayConnectivity();
    return failed;
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
      _updateRelayConnectivity();
      return connected;
    }

    RelayConnectivity? relayConnectivity = _globalState.relays[key];
    if (relayConnectivity != null && relayConnectivity.relayTransport != null) {
      try {
        final opened = await _waitForTransportOpen(
          relayConnectivity.relayTransport!,
          timeoutSeconds: DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
        );
        if (opened && relayConnectivity.relayTransport!.isOpen()) {
          _updateRelayConnectivity();
          return true;
        }
      } catch (error) {
        Logger.log.e(() => "error connecting to $key: $error");
      }
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
        _updateRelayConnectivity();
        return false;
      }

      if (!key.isAnonymous) {
        final account = as ?? _accountFor(key);
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
      relayConnectivity = _globalState.relays[key];
      if (relayConnectivity == null ||
          relayConnectivity.relayTransport == null ||
          !relayConnectivity.relayTransport!.isOpen()) {
        // web socket is not open
        return false;
      }
    }
    return true;
  }

  /// Closes and clears only transport-scoped state of every connection to
  /// [url], while keeping the entries and relay-scoped metadata in memory.
  Future<void> resetTransport(String url) async {
    await Future.wait(_connectionKeysForRelay(url).map(resetConnection));
  }

  /// Closes and clears only transport-scoped state of one connection, while
  /// keeping its entry and relay-scoped metadata in memory.
  Future<void> resetConnection(RelayConnectionKey key) async {
    final connectivity = _globalState.relays[key];
    if (connectivity != null) {
      Logger.log.d(() => "Resetting transport for $key...");
      connectivity.relay.failedToConnect();
      _forgetAuthState(key);
      await connectivity.close();
      _endAuthRetriesLeftBehind(key);
      _updateRelayConnectivity();
    }
  }

  /// every connection currently held towards [url]
  List<RelayConnectionKey> _connectionKeysForRelay(String url) {
    final relayUrl = RelayConnectionKey.anonymous(url).url;
    return _globalState.relays.keys
        .where((key) => key.url == relayUrl)
        .toList();
  }

  /// Reconnects all given relays
  Future<void> reconnectRelays(Iterable<String> urls) async {
    final startTime = DateTime.now();
    Logger.log.d(() => "connecting ${urls.length} relays in parallel");
    List<bool> connected = await Future.wait(
      urls.map((url) => reconnectRelay(url, force: true)),
    );
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    Logger.log.d(
      () =>
          "CONNECTED ${connected.where((element) => element).length} , ${connected.where((element) => !element).length} FAILED, took ${duration.inMilliseconds} ms",
    );
  }

  /// Reconnects every connection that is not connected, even one that just
  /// failed to, and replays the requests it was carrying. Call this when the
  /// app learns that the network is back.
  Future<void> reconnectClosedConnections() async {
    for (final connectivity in _globalState.relays.values.toList()) {
      if (connectivity.isConnected) continue;
      final connected = await reconnectConnection(
        connectivity.key,
        force: true,
      );
      _updateRelayConnectivity();
      if (connected) _reSubscribeInFlightSubscriptions(connectivity);
    }
  }

  /// Puts back on [relayConnectivity] what the socket it replaces still owed us:
  /// its subscriptions, and the queries that never got their EOSE.
  void _reSubscribeInFlightSubscriptions(RelayConnectivity relayConnectivity) {
    final transport = relayConnectivity.relayTransport;
    if (transport == null || !transport.isOpen()) {
      return;
    }

    _globalState.inFlightRequests.forEach((key, state) {
      state.requests.values
          // by connection, not by relay: replaying a bound request on the
          // anonymous socket gets it refused, and replaying an anonymous one on
          // a bound socket makes it attributable. An entry the relay already
          // refused stays refused, replaying it only retriggers the re-route,
          // unless it was refused for an authentication that never landed.
          .where(
            (req) =>
                req.key == relayConnectivity.key &&
                (!req.receivedClosed || req.retryingAuth) &&
                // a query is over once this connection answered EOSE, while a
                // subscription outlives its EOSE and has to go back up
                (state.isSubscription || !req.receivedEOSE),
          )
          .forEach((req) => _sendRequest(relayConnectivity, state.id, req));
    });
  }

  /// Writes [data] and tells whether it reached the transport
  bool _sendRaw(
    RelayConnectivity relayConnectivity,
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
  Future<void> _sendOrThrow(
    RelayConnectivity relayConnectivity,
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
  void _countRequest(
    RelayConnectivity relayConnectivity,
    List<dynamic> message,
  ) {
    switch (message) {
      case [ClientMsgType.kReq, final String id, ...]:
        relayConnectivity.stats.openRequestIds.add(id);
        for (final waiter
            in _requestSentWaiters.remove(id) ?? <Completer<void>>{}) {
          waiter.complete();
        }
      case [ClientMsgType.kClose, final String id, ...]:
        relayConnectivity.stats.openRequestIds.remove(id);
    }
  }

  /// Waits until a REQ with [id] is sent on a connected relay.
  Future<void> waitForRequestSent(String id, Duration timeout) async {
    if (_globalState.relays.values.any(
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

  /// Sends [message], a JSON array such as `["NEG-CLOSE", subscriptionId]`, on
  /// the connection behind [key] once its socket is ready. It is dropped, and
  /// logged, when there is no such connection or its socket goes away first.
  void send(RelayConnectionKey key, List<dynamic> message) {
    final relayConnectivity = getConnectivity(key);
    if (relayConnectivity == null) {
      Logger.log.t(() => "skip send to $key: no such connection");
      return;
    }
    _send(relayConnectivity, message);
  }

  void _send(RelayConnectivity relayConnectivity, List<dynamic> message) {
    unawaited(
      _sendOrThrow(relayConnectivity, message).catchError((Object error) {
        Logger.log.t(() => "skip send to ${relayConnectivity.url}: $error");
      }),
    );
  }

  /// Tracks [relayUrl] in [broadcastState], so its OK can be routed back.
  void _registerRelayBroadcast({
    required BroadcastState broadcastState,
    required String relayUrl,
    required Nip01Event eventToPublish,
  }) {
    // Store the event for potential retries on auth-required
    broadcastState.event ??= eventToPublish;

    // new tracking
    if (broadcastState.broadcasts[relayUrl] == null) {
      broadcastState.broadcasts[relayUrl] = RelayBroadcastResponse(
        relayUrl: relayUrl,
      );
    } else {
      // do not overwrite
      Logger.log.w(
        () =>
            "_registerRelayBroadcast: relay broadcast already registered for ${eventToPublish.id} $relayUrl, skipping",
      );
    }
  }

  /// use this to signal a failed broadcast
  void _failBroadcast(BroadcastState broadcastState, String relay, String msg) {
    if (broadcastState.networkController.isClosed) {
      Logger.log.w(
        () =>
            "Ignoring late failed broadcast for ${broadcastState.event?.id} on $relay because the broadcast controller is already closed",
      );
      return;
    }

    broadcastState.networkController.add(
      RelayBroadcastResponse(
        relayUrl: relay,
        okReceived: false,
        broadcastSuccessful: false,
        msg: msg,
      ),
    );
  }

  /// Tracks [state] as a broadcast of [eventId] until it is done, so the OK of
  /// the relays reach it.
  void _trackBroadcast(String eventId, BroadcastState state) {
    _globalState.inFlightBroadcasts.putIfAbsent(eventId, () => []).add(state);
    void untrack() {
      final states = _globalState.inFlightBroadcasts[eventId];
      if (states == null) return;
      states.remove(state);
      if (states.isEmpty) _globalState.inFlightBroadcasts.remove(eventId);
    }

    state.publishDoneFuture.then(
      (_) => untrack(),
      onError: (_, _) => untrack(),
    );
  }

  /// Sends [event] to [url] for [state], on the connection its [AuthPolicy]
  /// allows. The relay is tracked before this returns, and reported as failed
  /// when the EVENT cannot go out.
  ///
  /// [veto] is asked once the connection is up: a reason it gives not to send
  /// after all fails the relay with that reason.
  Future<void> _publishToRelay(
    BroadcastState state,
    String url,
    Nip01Event event, {
    int connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
    Future<String?> Function()? veto,
  }) async {
    _registerRelayBroadcast(
      broadcastState: state,
      eventToPublish: event,
      relayUrl: url,
    );
    try {
      final relay = await _connectionForBroadcast(
        url,
        state.auth,
        connectTimeout: connectTimeout,
        pausing: state,
      );
      if (relay == null) {
        final auth = state.auth;
        _failBroadcast(
          state,
          url,
          auth is AuthPolicyRequire
              ? "no connection bound to ${auth.account.pubkey} could be opened"
              : "could not connect",
        );
        return;
      }
      final vetoed = await veto?.call();
      if (vetoed != null) {
        _failBroadcast(state, url, vetoed);
        return;
      }
      await _sendOrThrow(
        relay,
        ClientMsg(ClientMsgType.kEvent, event: event).toJson(),
      );
    } catch (error) {
      _failBroadcast(state, url, "broadcast error: $error");
    }
  }

  /// Whether [connectivity] is still the connection tracked under its key, and
  /// [transport] still the one it runs on: anything a replaced one reports is
  /// stale.
  bool _isCurrent(RelayConnectivity? connectivity, NostrTransport? transport) =>
      connectivity != null &&
      transport != null &&
      identical(_globalState.relays[connectivity.key], connectivity) &&
      identical(connectivity.relayTransport, transport);

  void _startListeningToSocket(RelayConnectivity relayConnectivity) {
    final transport = relayConnectivity.relayTransport;
    relayConnectivity.listen(
      (message) {
        if (!_isCurrent(relayConnectivity, transport)) return;
        _handleIncomingMessage(message, relayConnectivity);
      },
      onError: (error) {
        if (!_isCurrent(relayConnectivity, transport)) return;
        Logger.log.e(() => "onError ${relayConnectivity.url} on listen $error");
        relayConnectivity.stats.connectionErrors++;
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
    RelayConnectivity relayConnectivity,
    NostrTransport? transport,
  ) async {
    if (!_isCurrent(relayConnectivity, transport)) return;

    try {
      await relayConnectivity.close();
    } catch (e) {
      Logger.log.w(() => "Error closing relay ${relayConnectivity.url}: $e");
    }
    // Closing can yield while a new owner or transport takes over. Its AUTH
    // and subscriptions belong to the replacement, not this retired socket.
    if (!identical(
          _globalState.relays[relayConnectivity.key],
          relayConnectivity,
        ) ||
        relayConnectivity.relayTransport != null) {
      return;
    }
    // the socket is gone, so is the AUTH the relay accepted on it
    _forgetAuthState(relayConnectivity.key);
    _updateRelayConnectivity();
    // Reconnect on close. close() above nulls relayTransport, so the only
    // condition is that the relay is still tracked: deliberate closes cancel
    // the stream subscription first and never reach this handler.
    if (allowReconnectRelays &&
        _globalState.relays[relayConnectivity.key] != null) {
      Logger.log.i(() => "closed ${relayConnectivity.url}. Reconnecting");
      reconnectConnection(relayConnectivity.key).then((connected) {
        _updateRelayConnectivity();
        if (connected) {
          _reSubscribeInFlightSubscriptions(relayConnectivity);
        }
        _endAuthRetriesLeftBehind(relayConnectivity.key);
        if (!connected) {
          _endRequestsLeftBehind(relayConnectivity.key);
        }
      });
      return;
    }
    _endAuthRetriesLeftBehind(relayConnectivity.key);
    _endRequestsLeftBehind(relayConnectivity.key);
  }

  /// Gives up on the requests that were still waiting for [key] to replay them.
  /// A request the replacement socket took back has stopped retrying by now, so
  /// what is left here is what nothing will send again.
  void _endAuthRetriesLeftBehind(RelayConnectionKey key) {
    for (final state in _globalState.inFlightRequests.values.toList()) {
      final request = state.requests[key];
      if (request == null || !request.retryingAuth) {
        continue;
      }
      request.retryingAuth = false;
      _checkNetworkClose(state);
    }
  }

  /// Gives up on the requests [key] still owed us once nothing will bring that
  /// connection back. They are reported as disconnected right away instead of
  /// waiting for a completion event no relay will send, or for the timeout.
  void _endRequestsLeftBehind(RelayConnectionKey key) {
    for (final state in _globalState.inFlightRequests.values.toList()) {
      final request = state.requests[key];
      if (request == null ||
          request.retryingAuth ||
          request.receivedEOSE ||
          request.receivedClosed ||
          request.notSent) {
        continue;
      }
      request.connectionGone = true;
      _checkNetworkClose(state);
    }
  }

  // Track processing order per relay so EVENT/EOSE/AUTH/CLOSED ordering stays
  // correct without introducing cross-relay head-of-line blocking.
  final Map<String, Completer<void>> _lastMessageCompleters = {};

  Future<void> _handleIncomingMessage(
    dynamic message,
    RelayConnectivity relayConnectivity,
  ) async {
    final relayUrl = relayConnectivity.url;
    final previousMessage = _lastMessageCompleters[relayUrl];

    final myCompleter = Completer<void>();
    _lastMessageCompleters[relayUrl] = myCompleter;

    NostrMessageRaw nostrMsg;
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

    if (previousMessage != null) {
      await previousMessage.future;
    }
    try {
      await _processDecodedMessage(nostrMsg, relayConnectivity, message);
    } finally {
      if (!myCompleter.isCompleted) {
        myCompleter.complete();
      }
      if (identical(_lastMessageCompleters[relayUrl], myCompleter)) {
        _lastMessageCompleters.remove(relayUrl);
      }
    }
  }

  Future<void> _processDecodedMessage(
    NostrMessageRaw nostrMsg,
    RelayConnectivity relayConnectivity,
    dynamic message,
  ) {
    if (nostrMsg.type == NostrMessageRawType.unknown) {
      final data = nostrMsg.otherData;
      if (data is List &&
          List.of(
            _protocolHandlers,
          ).any((handler) => handler.onMessage(relayConnectivity.key, data))) {
        return Future.value();
      }
      Logger.log.w(
        () =>
            "Received non NostrMessageRaw message from ${relayConnectivity.url}: $nostrMsg",
      );
      return Future.value();
    }

    if (nostrMsg.type == NostrMessageRawType.ok) {
      final eventJson = nostrMsg.otherData;
      final String eventId = eventJson[1];
      final bool success = eventJson[2] == true;
      final String? msg = eventJson.length > 3 ? eventJson[3] : null;

      // an AUTH is only answered by the connection it was sent on
      final session = _authSessions[relayConnectivity.key];
      if (session != null && session.receiveOk(eventId, success)) {
        if (success) {
          Logger.log.d(() => "AUTH OK for $eventId");
        } else {
          Logger.log.e(() => "AUTH failed for $eventId: $msg");
        }
        return Future.value();
      }

      //nip 20 used to notify clients if an EVENT was successful
      if (!success) {
        Logger.log.e(() => "NOT OK from ${relayConnectivity.url}: $eventJson");
      }
      _routeBroadcastOk(eventId, relayConnectivity, success, msg ?? '');
      return Future.value();
    }
    if (nostrMsg.type == NostrMessageRawType.notice) {
      final eventJson = nostrMsg.otherData;
      final noticeMsg = eventJson[1] as String? ?? '';
      Logger.log.w(() => "NOTICE from ${relayConnectivity.url}: $noticeMsg");
      _logActiveRequests();
      for (final handler in List.of(_protocolHandlers)) {
        handler.onNotice(relayConnectivity.key, noticeMsg);
      }
    } else if (nostrMsg.type == NostrMessageRawType.event) {
      _handleIncomingEvent(
        nostrMsg,
        relayConnectivity,
        message.toString().codeUnits.length,
      );
      // Logger.log.t(()=>"EVENT from ${relayConnectivity.url}: $eventJson");
    } else if (nostrMsg.type == NostrMessageRawType.eose) {
      final eventJson = nostrMsg.otherData;
      Logger.log.d(() => "EOSE from ${relayConnectivity.url}: ${eventJson[1]}");
      _handleEOSE(eventJson, relayConnectivity);
    } else if (nostrMsg.type == NostrMessageRawType.closed) {
      final eventJson = nostrMsg.otherData;
      Logger.log.w(
        () =>
            " CLOSED subscription url: ${relayConnectivity.url} id: ${eventJson[1]} msg: ${eventJson.length > 2 ? eventJson[2] : ''}",
      );
      _handleClosed(eventJson, relayConnectivity);
    }
    if (nostrMsg.type == NostrMessageRawType.auth) {
      final eventJson = nostrMsg.otherData;
      // nip 42 used to send authentication challenges
      final challenge = eventJson[1];
      Logger.log.d(
        () => "AUTH challenge from ${relayConnectivity.key}: $challenge",
      );

      _authSessionOf(relayConnectivity.key).receiveChallenge(challenge);

      // an anonymous connection never answers a challenge: signing here would
      // bind it to an identity nobody asked for, and every request already on
      // it would become attributable. A bound one answers as soon as it can.
      if (!relayConnectivity.key.isAnonymous) {
        unawaited(authenticateConnection(relayConnectivity.key));
      }
      return Future.value();
    }
    return Future.value();
    //
    // if (eventJson[0] == 'COUNT') {
    //   log("COUNT: ${eventJson[1]}");
    //   // nip 45 used to send requested event counts to clients
    //   return;
    // }
  }

  /// Opens the connection towards [url] bound to [account]. The binding says
  /// which identity this socket may ever assume, not that it is already
  /// authenticated: relays are free to send their challenge whenever they want,
  /// and some only send it once a request needs it.
  ///
  /// A new binding is first put to [authHandler], with [pausing] paused while
  /// it decides. A connection that already exists was agreed to when it was
  /// first opened, so reconnecting it does not ask again.
  Future<RelayConnectivity?> openConnectionAs(
    String url,
    Account account, {
    int connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
    TimeoutPausable? pausing,
  }) async {
    if (!account.signer.canSign()) {
      Logger.log.w(() => "Cannot bind a connection to ${account.pubkey}");
      return null;
    }
    final key = RelayConnectionKey.authenticated(url, account.pubkey);
    if (_globalState.relays[key] == null &&
        !await _consent(key, pausing: pausing)) {
      Logger.log.d(() => "Not allowed to open $key");
      return null;
    }
    _boundAccounts[key] = account;

    if (isConnectionOpen(key)) {
      return _globalState.relays[key];
    }

    final result = await connectRelay(
      dirtyUrl: url,
      authPubkey: account.pubkey,
      connectTimeout: connectTimeout,
    );
    final connectivity = _globalState.relays[key];
    if (!result.connected || connectivity == null) {
      Logger.log.w(() => "Could not open $key: ${result.error}");
      return null;
    }
    return connectivity;
  }

  Future<bool> _consent(
    RelayConnectionKey key, {
    TimeoutPausable? pausing,
  }) async {
    final handler = authHandler;
    if (handler == null) {
      return true;
    }
    var asking = _consents[key];
    if (asking == null) {
      final question = _ask(handler, key);
      _consents[key] = asking = question;
      question.whenComplete(() {
        if (identical(_consents[key], question)) {
          _consents.remove(key);
        }
      });
    }
    pausing?.pauseTimeout();
    try {
      return await asking;
    } finally {
      pausing?.resumeTimeout();
    }
  }

  Future<bool> _ask(AuthHandler handler, RelayConnectionKey key) async {
    try {
      return await handler(key.url, key.pubkey!);
    } catch (error, stackTrace) {
      Logger.log.w(
        () => "AuthHandler failed for $key",
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// The connection a broadcast under [auth] must go out on towards [url],
  /// opening it when it is not there yet. Null means nothing may be sent.
  ///
  /// Owns the connecting too: a broadcast that requires an identity must not
  /// even open the anonymous connection, because a socket we opened is one the
  /// relay saw, whether or not anything was sent on it.
  Future<RelayConnectivity?> _connectionForBroadcast(
    String url,
    AuthPolicy? auth, {
    int connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
    TimeoutPausable? pausing,
  }) async {
    if (auth is AuthPolicyRequire) {
      if (!auth.account.signer.canSign()) {
        Logger.log.w(
          () => "Broadcast requires ${auth.account.pubkey}, which cannot sign",
        );
        return null;
      }
      return openConnectionAs(
        url,
        auth.account,
        connectTimeout: connectTimeout,
        pausing: pausing,
      );
    }

    if (!isRelayConnected(url)) {
      final result = await connectRelay(
        dirtyUrl: url,
        connectTimeout: connectTimeout,
      );
      if (!result.connected) {
        Logger.log.w(() => "Could not connect to $url: ${result.error}");
        return null;
      }
    }
    return getRelayConnectivity(url);
  }

  /// The account [key] authenticates as. A registered account wins, because
  /// [AuthAccounts] owns its signer's lifetime; otherwise it is the one the
  /// caller handed to [AuthPolicy], which never had to be registered. Both
  /// carry [RelayConnectionKey.pubkey], so this only picks a signer, never an
  /// identity.
  Account? _accountFor(RelayConnectionKey key) =>
      _accounts?.accounts[key.pubkey] ?? _boundAccounts[key];

  _AuthSession _authSessionOf(RelayConnectionKey key) =>
      _authSessions.putIfAbsent(
        key,
        () => _AuthSession(
          key,
          challengeTimeout: authChallengeTimeout,
          okTimeout: authCallbackTimeout,
        ),
      );

  bool _isAuthenticated(RelayConnectionKey key) =>
      _authSessions[key]?.authenticated ?? false;

  /// Ends the NIP-42 session of [key]'s socket. Call this whenever the socket
  /// dies or gets replaced: what is still in flight then resolves to false
  /// instead of landing on the socket that took its place.
  void _forgetAuthState(RelayConnectionKey key) =>
      _authSessions.remove(key)?.end();

  /// Answers the challenge for [key] and completes once the relay accepted the
  /// AUTH event. Concurrent callers share a single AUTH.
  Future<bool> authenticateConnection(RelayConnectionKey key) {
    final connectivity = _globalState.relays[key];
    if (key.isAnonymous || connectivity == null) {
      return Future.value(false);
    }
    return _authSessionOf(
      key,
    ).authenticate(_accountFor(key), (message) => _send(connectivity, message));
  }

  void _handleIncomingEvent(
    NostrMessageRaw nostrMsgRaw,
    RelayConnectivity connectivity,
    int messageSize,
  ) {
    final requestId = nostrMsgRaw.requestId!;
    final event = nostrMsgRaw.nip01Event!;

    if (_globalState.inFlightRequests[requestId] == null) {
      Logger.log.w(
        () =>
            "RECEIVED EVENT from ${connectivity.url} for id $requestId, not in flight. Likely data after EOSE on a query",
      );
      return;
    }

    connectivity.stats.incStatsByNewEvent(event, messageSize);

    RequestState? state = _globalState.inFlightRequests[requestId];
    if (state != null) {
      RelayRequestState? request = state.requests[connectivity.key];
      if (request == null) {
        Logger.log.w(() => "No RelayRequestState found for id $requestId");
        return;
      }

      final eventWithSources = event.copyWith(
        sources: [...event.sources, connectivity.url],
      );

      if (state.networkController.isClosed) {
        // this might happen because relays even after we send a CLOSE subscription.id, they'll still send more events
        Logger.log.t(
          () => "tried to add event to an already closed STREAM ${state.id}",
        );
      } else {
        state.networkController.add(eventWithSources);
      }
    }
  }

  /// handles EOSE messages
  void _handleEOSE(
    List<dynamic> eventJson,
    RelayConnectivity relayConnectivity,
  ) {
    String id = eventJson[1];
    RequestState? state = _globalState.inFlightRequests[id];
    if (state != null && state.closeOnEose) {
      Logger.log.t(
        () =>
            "⛁ received EOSE from ${relayConnectivity.url} for REQ id $id, remaining requests from :${state.requests.keys} kind:${state.requests.values.first.filters.first.kinds}",
      );
      RelayRequestState? request = state.requests[relayConnectivity.key];
      if (request != null) {
        request.receivedEOSE = true;
      }

      if (state.closeOnEose) {
        _sendCloseToRelay(relayConnectivity, state.id);
        _checkNetworkClose(state);
        _logActiveRequests();
      }
    }
    return;
  }

  /// handles CLOSED messages
  void _handleClosed(
    List<dynamic> eventJson,
    RelayConnectivity relayConnectivity,
  ) {
    String id = eventJson[1];
    String? message = eventJson.length > 2 ? eventJson[2] : null;

    // a protocol session is not a REQ: it owns its own retry and never has a
    // RequestState for the auth branch below to find
    for (final handler in List.of(_protocolHandlers)) {
      if (handler.onClosed(relayConnectivity.key, id, message)) return;
    }

    // Check if this is an auth-required CLOSED message
    if (message != null && message.startsWith("auth-required")) {
      _handleClosedAuthRequired(id, relayConnectivity, message);
      return;
    }

    RequestState? state = _globalState.inFlightRequests[id];
    if (state != null) {
      Logger.log.t(
        () =>
            "⛁ received CLOSE from ${relayConnectivity.url} for REQ id $id, remaining requests from :${state.requests.keys} kind:${state.requests.values.first.filters.first.kinds}",
      );
      RelayRequestState? request = state.requests[relayConnectivity.key];
      if (request != null) {
        _endRequestOnRelay(relayConnectivity, id, request, message);
      }

      _checkNetworkClose(state);
      _logActiveRequests();
    }
    return;
  }

  /// Sends [request] on [relayConnectivity] and tracks it as open there
  void _sendRequest(
    RelayConnectivity relayConnectivity,
    String reqId,
    RelayRequestState request,
  ) {
    request.markSent();
    _send(
      relayConnectivity,
      ClientMsg(
        ClientMsgType.kReq,
        id: reqId,
        filters: request.filters,
      ).toJson(),
    );
  }

  /// Marks what the relay itself ended with a CLOSED. It stops counting as open
  /// on that connection, and there is no CLOSE left for us to send.
  void _endRequestOnRelay(
    RelayConnectivity relayConnectivity,
    String reqId,
    RelayRequestState request,
    String? message,
  ) {
    request.markClosed(message);
    relayConnectivity.stats.openRequestIds.remove(reqId);
  }

  /// Whether [state] is still the request tracked under its id. A request
  /// closed while an authentication or a connection was pending must not be
  /// sent afterwards: nothing tracks it anymore, so nothing would ever CLOSE it.
  bool _isStillInFlight(RequestState state) =>
      identical(_globalState.inFlightRequests[state.id], state);

  /// Announces a send path that has yet to work out which connection to use,
  /// so a relay answering meanwhile does not look like the only one this
  /// request ever had. Pair every call with [_endPendingConnection].
  void _beginPendingConnection(RequestState state) =>
      state.pendingConnections++;

  /// Ends what [_beginPendingConnection] announced, and reconsiders closing the
  /// request. A path that gave up without registering anything is the last
  /// thing that can notice: nothing else runs when a connection simply never
  /// opened.
  void _endPendingConnection(RequestState state) {
    state.pendingConnections--;
    _checkNetworkClose(state);
  }

  /// Gives up on sending [state] on [key] because of [reason], tracking the
  /// request there first if it is not yet. The relay keeps its place in the
  /// outcomes as notSent and stops holding the request open, so a request none
  /// of its relays could carry ends right away.
  void _failRelayRequest(
    RequestState state,
    RelayConnectionKey key,
    List<Filter> filters,
    String reason,
  ) {
    if (!_isStillInFlight(state)) return;
    state.addRequest(key, filters);
    state.requests[key]!.markNotSent(reason);
    _checkNetworkClose(state);
  }

  /// Sends [filters] to [url] for [state], on the connection its [AuthPolicy]
  /// allows. The relay is tracked before this returns, so a request sealed
  /// right after does not end on it.
  ///
  /// Each relay takes one call: [filters] travel in a single REQ, since a
  /// second REQ with the same id would replace the first on the relay.
  Future<void> _sendRequestToRelay(
    RequestState state,
    String url,
    List<Filter> filters,
  ) async {
    // a relay an engine handed over late, once the request is over, must not
    // revive it: nothing would ever CLOSE that REQ
    if (!_isStillInFlight(state) || state.networkController.isClosed) return;
    final auth = state.auth;
    final key = RelayConnectionKey.forAuth(url, auth);
    if (key == null) {
      final account = (auth as AuthPolicyRequire).account;
      _failRelayRequest(
        state,
        RelayConnectionKey.authenticated(url, account.pubkey),
        filters,
        "requires ${account.pubkey}, which cannot sign",
      );
      return;
    }
    if (state.requests.containsKey(key)) {
      throw StateError("${state.id} was already sent to $key");
    }
    state.addRequest(key, filters);
    await _sendTracked(state, state.requests[key]!);
  }

  /// Sends [request], already tracked by [state], to its relay. One it cannot
  /// be sent to is reported as notSent before the send path ends, so the
  /// request never closes on that relay as merely disconnected.
  Future<void> _sendTracked(
    RequestState state,
    RelayRequestState request,
  ) async {
    // a connection that is still opening is not one that is gone, and
    // _checkNetworkClose cannot tell them apart on its own
    _beginPendingConnection(state);
    try {
      final notSentReason = await _sendTrackedRequest(state, request);
      if (notSentReason != null) {
        _failRelayRequest(state, request.key, request.filters, notSentReason);
      }
    } finally {
      _endPendingConnection(state);
    }
  }

  /// Null once sent, otherwise what kept [request] from being sent.
  Future<String?> _sendTrackedRequest(
    RequestState state,
    RelayRequestState request,
  ) async {
    if (_globalState.blockedRelays.contains(request.url)) {
      Logger.log.w(
        () => "COULD NOT SEND REQUEST TO ${request.url} since relay is blocked",
      );
      return "relay is blocked";
    }

    final connected = await reconnectConnection(
      request.key,
      force: false,
      as: state.auth?.account,
      pausing: state,
    );
    // a timeout or a close may have ended the request while the connection
    // was opening: nothing tracks it anymore, so nothing would ever CLOSE what
    // we would send here
    if (!_isStillInFlight(state)) {
      return "request ended while connecting";
    }
    if (!connected) {
      Logger.log.e(
        () =>
            "COULD NOT SEND REQUEST TO ${request.url} since socket seems to be not open",
      );
      return "could not connect";
    }
    final relay = _globalState.relays[request.key];
    if (relay == null) {
      Logger.log.w(
        () =>
            "COULD NOT SEND REQUEST TO ${request.url}, ${request.key} is gone",
      );
      return "connection closed before sending";
    }
    try {
      await _sendOrThrow(
        relay,
        ClientMsg(
          ClientMsgType.kReq,
          id: state.id,
          filters: request.filters,
        ).toJson(),
      );
    } catch (e) {
      Logger.log.e(() => "COULD NOT SEND REQUEST TO ${request.url}:", error: e);
      return "$e";
    }
    return null;
  }

  /// Sends a CLOSE wherever [state] is still open on a relay, then ends it.
  Future<void> _closeRequest(RequestState state) async {
    for (final relay in connectedRelays) {
      final request = state.requests[relay.key];
      if (request == null) continue;
      // a request the relay ended itself, with a CLOSED or with the EOSE of a
      // query, is already closed on its side
      final endedOnRelay =
          request.receivedClosed || (state.closeOnEose && request.receivedEOSE);
      if (endedOnRelay) continue;
      _sendCloseToConnection(relay.key, state.id);
    }

    await state.close();
    if (identical(_globalState.inFlightRequests[state.id], state)) {
      _globalState.inFlightRequests.remove(state.id);
    }
    if (identical(_openReqs[state.id]?._state, state)) {
      _openReqs.remove(state.id);
    }
  }

  /// Handles CLOSED auth-required.
  ///
  /// A connection is bound to at most one identity, and that binding never
  /// changes. An anonymous connection therefore hands the request over to a
  /// bound one, while a bound connection answers the challenge itself.
  void _handleClosedAuthRequired(
    String reqId,
    RelayConnectivity relayConnectivity,
    String message,
  ) {
    final state = _globalState.inFlightRequests[reqId];
    if (state == null) {
      Logger.log.w(
        () => "Received CLOSED auth-required for unknown request $reqId",
      );
      return;
    }

    final key = relayConnectivity.key;
    final request = state.requests[key];
    if (request == null) {
      Logger.log.w(
        () => "Received CLOSED auth-required but no request state for $key",
      );
      return;
    }

    // whatever we do next, the relay just closed this one on this connection
    _endRequestOnRelay(relayConnectivity, reqId, request, message);

    if (!key.isAnonymous) {
      final session = _authSessionOf(key);
      if (session.authenticated) {
        // the relay refused us while we were authenticated as the only identity
        // this connection may ever assume, so there is nothing left to try
        Logger.log.w(() => "REQ $reqId refused on authenticated $key");
        _checkNetworkClose(state);
        return;
      }

      Logger.log.d(() => "Authenticating $key to satisfy REQ $reqId");
      state.pauseTimeout();
      request.retryingAuth = true;
      authenticateConnection(key).then((authenticated) {
        if (!_isStillInFlight(state)) {
          return;
        }
        state.resumeTimeout();
        if (!authenticated) {
          // an authentication that died with its socket is not a refusal: stay
          // on the retry so the replacement replays the request
          request.retryingAuth = session.ended;
          _checkNetworkClose(state);
          return;
        }
        _sendRequest(relayConnectivity, reqId, request);
      });
      return;
    }

    final account = _accountForRequest(state);
    if (account == null) {
      Logger.log.w(() => "Cannot satisfy auth-required for REQ $reqId on $key");
      _checkNetworkClose(state);
      return;
    }

    final target = RelayConnectionKey.authenticated(key.url, account.pubkey);
    state.addRequest(target, request.filters);

    Logger.log.d(
      () => "AUTH required for REQ $reqId on $key, retrying on $target",
    );

    state.pauseTimeout();
    _beginPendingConnection(state);
    openConnectionAs(key.url, account).then((bound) {
      try {
        if (!_isStillInFlight(state)) {
          return;
        }
        state.resumeTimeout();
        final retry = state.requests[target];
        if (retry == null) {
          return;
        }
        if (bound == null) {
          retry.markClosed(
            "auth-required: no authenticated connection could be opened",
          );
          return;
        }
        // sent without waiting for the AUTH: a relay that only challenges on
        // demand needs this request as the trigger, and the refusal that may
        // follow lands on the branch above
        _sendRequest(bound, reqId, retry);
      } finally {
        _endPendingConnection(state);
      }
    });
  }

  /// Account a request authenticates as, null when it must stay unattributable.
  Account? _accountForRequest(RequestState state) => accountForAuth(state.auth);

  /// Account [auth] authenticates as, null when it must stay unattributable.
  Account? accountForAuth(AuthPolicy? auth) {
    switch (auth) {
      case AuthPolicyNever():
        return null;
      case AuthPolicyAllow(:final account):
      case AuthPolicyRequire(:final account):
        return account.signer.canSign() ? account : null;
      case null:
        // a request that says nothing reveals nothing unless an AuthHandler is
        // there to agree to it
        return authHandler == null ? null : _loggedSigner();
    }
  }

  Account? _loggedSigner() {
    final logged = _accounts?.getLoggedAccount();
    return logged != null && logged.signer.canSign() ? logged : null;
  }

  /// Account a broadcast authenticates as, null when it must stay
  /// unattributable.
  ///
  /// A caller that named an identity gets that one, with no heuristic. Only a
  /// broadcast that said nothing prefers the event author, because gift wraps
  /// and other ephemeral-author events have no matching account, and only once
  /// an [AuthHandler] is there to agree to it.
  Account? _accountForBroadcast(BroadcastState state, Nip01Event event) {
    if (state.auth != null) {
      return accountForAuth(state.auth);
    }
    if (authHandler == null) {
      return null;
    }

    final author = _accounts?.accounts[event.pubKey];
    if (author != null && author.signer.canSign()) {
      return author;
    }
    return _loggedSigner();
  }

  /// A relay answers every EVENT it receives, and the same event can be in
  /// flight in several broadcasts. An acceptance means the relay holds the
  /// event, so it answers all of them; a refusal answers a single EVENT.
  void _routeBroadcastOk(
    String eventId,
    RelayConnectivity relayConnectivity,
    bool success,
    String msg,
  ) {
    final waiting = _broadcastsWaitingOn(eventId, relayConnectivity.url);
    if (waiting.isEmpty) {
      Logger.log.w(
        () =>
            "Received OK for broadcast $eventId from ${relayConnectivity.url} but no broadcast is waiting for it",
      );
      return;
    }

    // not an answer yet: each broadcast retries under its own auth policy
    if (!success && msg.startsWith("auth-required")) {
      for (final broadcastState in waiting) {
        _handleBroadcastAuthRequired(broadcastState, relayConnectivity);
      }
      return;
    }

    for (final broadcastState in success ? waiting : waiting.take(1)) {
      broadcastState.networkController.add(
        RelayBroadcastResponse(
          relayUrl: relayConnectivity.url,
          okReceived: true,
          broadcastSuccessful: success,
          msg: msg,
        ),
      );
    }
  }

  /// In-flight broadcasts of [eventId] sent to [relayUrl] that have no answer
  /// from it yet.
  List<BroadcastState> _broadcastsWaitingOn(String eventId, String relayUrl) {
    final states = _globalState.inFlightBroadcasts[eventId] ?? const [];
    return states
        .where(
          (state) =>
              !state.networkController.isClosed &&
              state.broadcasts.values.any(
                (response) =>
                    cleanRelayUrl(response.relayUrl) == relayUrl &&
                    !response.okReceived &&
                    response.msg.isEmpty,
              ),
        )
        .toList();
  }

  /// Handles OK auth-required for a broadcast by moving the retry onto an
  /// account-bound connection, authenticating it once, and re-sending EVENT.
  /// Concurrent broadcasts share [authenticateConnection], avoiding duplicate
  /// AUTH events whose identical ids used to overwrite each other's callbacks.
  void _handleBroadcastAuthRequired(
    BroadcastState broadcastState,
    RelayConnectivity relayConnectivity,
  ) {
    final relayUrl = relayConnectivity.url;
    // the refusal of another broadcast of the same event reaches this one too
    if (broadcastState.retryingAuth.contains(relayUrl)) {
      return;
    }

    final eventToResend = broadcastState.event;
    if (eventToResend == null) {
      Logger.log.w(
        () =>
            "Received OK auth-required from $relayUrl but no event stored for the broadcast",
      );
      return;
    }
    final eventId = eventToResend.id;

    final resolved = _accountForBroadcast(broadcastState, eventToResend);

    if (resolved == null) {
      Logger.log.w(
        () =>
            "Cannot satisfy auth-required for broadcast $eventId on $relayUrl",
      );
      _failBroadcast(
        broadcastState,
        relayUrl,
        'auth-required: this broadcast may not reveal an identity',
      );
      return;
    }
    final account = resolved;

    final boundKey = RelayConnectionKey.authenticated(relayUrl, account.pubkey);

    Future<void> retryOnBoundConnection() async {
      try {
        final bound = await openConnectionAs(
          relayUrl,
          account,
          pausing: broadcastState,
        );
        if (broadcastState.networkController.isClosed) {
          return;
        }
        if (bound == null) {
          _failBroadcast(broadcastState, relayUrl, 'auth connection failed');
          return;
        }

        // Some relays challenge immediately; others only after seeing EVENT on
        // the bound socket. Trigger the latter, then the next auth-required OK
        // enters this method with the bound key and authenticates below.
        if (relayConnectivity.key != boundKey && !_isAuthenticated(boundKey)) {
          await _sendOrThrow(
            bound,
            ClientMsg(ClientMsgType.kEvent, event: eventToResend).toJson(),
          );
          return;
        }

        final accepted = await authenticateConnection(boundKey);
        if (broadcastState.networkController.isClosed) {
          return;
        }
        if (!accepted) {
          _failBroadcast(broadcastState, relayUrl, 'authentication failed');
          return;
        }
        await _sendOrThrow(
          bound,
          ClientMsg(ClientMsgType.kEvent, event: eventToResend).toJson(),
        );
      } catch (error, stackTrace) {
        Logger.log.e(
          () => "Broadcast auth retry failed for $eventId",
          error: error,
          stackTrace: stackTrace,
        );
        if (!broadcastState.networkController.isClosed) {
          _failBroadcast(broadcastState, relayUrl, 'auth retry failed');
        }
      } finally {
        broadcastState.retryingAuth.remove(relayUrl);
      }
    }

    broadcastState.retryingAuth.add(relayUrl);
    unawaited(retryOnBoundConnection());
  }

  void _checkNetworkClose(RequestState state) {
    // a send path is still working out which connection to use, so the relays
    // registered so far are not all this request will ever have. Both branches
    // below would read that as finished
    if (state.pendingConnections > 0) {
      return;
    }

    /// received everything, close the network controller
    if (state.didAllRequestsFinish) {
      state.networkController.close();
      _updateRelayConnectivity();
      return;
    }

    /// check if relays for this request are still connected
    /// if not ignore it and wait for the ones still alive to finish. A
    /// connection that was dropped entirely counts as gone too, otherwise a
    /// request left on it would wait for a socket nobody will reopen. One that
    /// is retrying its authentication is the exception: its replacement is on
    /// its way and owes it a replay.
    final myNotConnectedRelays = state.requests.keys
        .where((key) => !isConnectionOpen(key))
        .toList();

    final bool didAllRelaysFinish = state.requests.values.every(
      (element) =>
          !element.retryingAuth &&
          (element.receivedEOSE ||
              element.receivedClosed ||
              element.notSent ||
              myNotConnectedRelays.contains(element.key)),
    );

    if (didAllRelaysFinish) {
      for (final key in myNotConnectedRelays) {
        final request = state.requests[key]!;
        if (!request.receivedEOSE &&
            !request.receivedClosed &&
            !request.notSent) {
          request.connectionGone = true;
        }
      }
      state.networkController.close();
      _updateRelayConnectivity();
    }
  }

  /// sends a close message on the connection the subscription was sent on
  void _sendCloseToConnection(RelayConnectionKey key, String id) {
    RelayConnectivity? connectivity = _globalState.relays[key];
    if (connectivity != null) {
      _sendCloseToRelay(connectivity, id);
    }
  }

  void _sendCloseToRelay(RelayConnectivity relayConnectivity, String id) {
    try {
      _send(
        relayConnectivity,
        ClientMsg(ClientMsgType.kClose, id: id).toJson(),
      );
    } catch (e) {
      Logger.log.e(() => e);
    }
  }

  void _logActiveRequests() {
    // Map<int?, int> kindsMap = {};
    Map<String?, int> namesMap = {};
    _globalState.inFlightRequests.forEach((key, state) {
      // int? kind;
      // if (state.requests.isNotEmpty &&
      //     state.requests.values.first.filters.first.kinds != null &&
      //     state.requests.values.first.filters.first.kinds!.isNotEmpty) {
      //   kind = state.requests.values.first.filters.first.kinds!.first;
      // }
      // int? kindCount = kindsMap[kind];
      int? nameCount = namesMap[state.name];
      // kindCount ??= 0;
      // kindCount++;
      nameCount ??= 0;
      nameCount++;
      // kindsMap[kind] = kindCount;
      namesMap[state.name] = nameCount;
    });
    Logger.log.d(
      () =>
          "------------ IN FLIGHT REQUESTS: ${_globalState.inFlightRequests.length} || $namesMap",
    );
  }

  /// Closes every connection towards [url] and forgets them
  Future<void> closeTransport(String url) async {
    await Future.wait(_connectionKeysForRelay(url).map(closeConnection));
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
      for (final key in _globalState.relays.keys.toList()) {
        // Re-evaluate after each asynchronous close. Another operation may
        // have claimed the next connection while the previous one was closing.
        if (_hasUnassignedConnectionWork()) break;
        if (_connectionHasWork(key)) continue;
        await closeConnection(key);
        changed = true;
      }
    } finally {
      if (changed) _updateRelayConnectivity();
    }
  }

  bool _hasUnassignedConnectionWork() {
    for (final state in _globalState.inFlightRequests.values) {
      if (!state.networkController.isClosed &&
          (state.pendingConnections > 0 || state.requests.isEmpty)) {
        return true;
      }
    }
    return _globalState.inFlightBroadcasts.values
        .expand((states) => states)
        .any(
          (state) =>
              !state.networkController.isClosed && state.broadcasts.isEmpty,
        );
  }

  bool _connectionHasWork(RelayConnectionKey key) {
    final connectivity = _globalState.relays[key];
    if (connectivity == null) return true;
    if (_connectReadyCompleters.containsKey(key) ||
        connectivity.relay.connecting ||
        (connectivity.relayTransport?.isConnecting() ?? false) ||
        (_authSessions[key]?.authenticating ?? false)) {
      return true;
    }
    for (final state in _globalState.inFlightRequests.values) {
      if (state.networkController.isClosed) continue;
      final request = state.requests[key];
      if (request != null &&
          (request.retryingAuth ||
              (!request.receivedClosed &&
                  (state.isSubscription || !request.receivedEOSE)))) {
        return true;
      }
    }
    for (final state in _globalState.inFlightBroadcasts.values.expand(
      (states) => states,
    )) {
      if (state.networkController.isClosed) continue;
      if (state.broadcasts.keys.any((url) => cleanRelayUrl(url) == key.url)) {
        return true;
      }
    }
    return _protocolHandlers.any((handler) => handler.hasWorkOn(key));
  }

  /// Closes one connection and forgets it. An entry that lost its transport, to
  /// a reset or to a failed connection attempt, is forgotten just the same:
  /// leaving it behind keeps its auth state alive and makes it reconnect.
  Future<void> closeConnection(RelayConnectionKey key) async {
    final connectivity = _globalState.relays.remove(key);
    if (connectivity == null) {
      return;
    }
    Logger.log.d(() => "Disconnecting $key...");
    _boundAccounts.remove(key);
    _forgetAuthState(key);
    _endAuthRetriesLeftBehind(key);
    return connectivity.close();
  }

  /// Closes all transports
  Future<void> closeAllTransports() async {
    final keys = _globalState.relays.keys.toList();
    try {
      await Future.wait(keys.map(closeConnection));
    } catch (e) {
      Logger.log.e(() => e);
    }
  }

  /// return [RelayConnectivity] by url
  RelayConnectivity? getRelayConnectivity(String url) {
    return _globalState.relays[RelayConnectionKey.anonymous(url)];
  }

  /// return [RelayConnectivity] of one connection, anonymous or bound
  RelayConnectivity? getConnectivity(RelayConnectionKey key) {
    return _globalState.relays[key];
  }
}
