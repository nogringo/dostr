import 'dart:async';
import 'dart:collection';

import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import '../domain_layer/entities/relay_connection_key.dart';
import '../domain_layer/entities/relay_failure.dart';
import '../domain_layer/entities/relay_req_event.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'client_msg.dart';
import 'nostr_message_raw.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';
import 'request_state.dart';

/// A request waiting for a slot on a connection, [order] telling which came
/// first.
typedef _Queued = ({int order, RequestState state, RelayRequestState request});

/// The requests waiting for a slot on one connection. Queries and
/// subscriptions wait apart, so a subscription held back by its share is
/// passed over without scanning the queries behind it.
class _Waiting {
  final queries = Queue<_Queued>();
  final subscriptions = Queue<_Queued>();

  bool get isEmpty => queries.isEmpty && subscriptions.isEmpty;

  Queue<_Queued> of(RequestState state) =>
      state.isSubscription ? subscriptions : queries;
}

/// The REQs in flight on a `RelayManager`: sending them, following what each
/// relay answers, replaying them on a new socket and moving them to a bound
/// connection when a relay asks for authentication. Internal to ndk_core.
///
/// A connection carries at most as many REQs as its relay accepts, the
/// others wait in its queue for a slot.
class RelayRequests implements ConnectionListener {
  final RelayConnections _connections;
  final RelayAuth _auth;

  /// holds the state of all in flight requests
  /// key: request Id
  final Map<String, RequestState> inFlight = {};

  final Map<RelayConnectionKey, _Waiting> _waiting = {};

  /// every request [_waiting] holds. One taken out of here stays in its queue
  /// until it reaches the head, where it is dropped.
  final Set<RelayRequestState> _queued = Set.identity();

  int _queuedSoFar = 0;

  RelayRequests({
    required RelayConnections connections,
    required RelayAuth auth,
  }) : _connections = connections,
       _auth = auth;

  /// Puts back on [relayConnectivity] what the socket it replaces still owed us:
  /// its subscriptions, and the queries that never got their EOSE.
  @override
  void replayOn(RelayConnection relayConnectivity) {
    final transport = relayConnectivity.relayTransport;
    if (transport == null || !transport.isOpen()) {
      return;
    }

    // what waited on the previous socket waits again below, in order
    _dropQueue(relayConnectivity.key);
    inFlight.forEach((key, state) {
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
                req.notSentFailure?.kind != RelayFailureKind.messageTooLong &&
                // a query is over once this connection answered EOSE, while a
                // subscription outlives its EOSE and has to go back up
                (state.isSubscription || !req.receivedEOSE),
          )
          .forEach((req) => unawaited(_admit(relayConnectivity, state, req)));
    });
  }

  /// Gives up on the requests that were still waiting for [key] to replay them.
  /// A request the replacement socket took back has stopped retrying by now, so
  /// what is left here is what nothing will send again.
  @override
  void endAuthRetriesOn(RelayConnectionKey key) {
    for (final state in inFlight.values.toList()) {
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
  @override
  void endRequestsOn(RelayConnectionKey key) {
    // a request waiting there ends as disconnected too: the connection died,
    // it was not full
    _dropQueue(key);
    for (final state in inFlight.values.toList()) {
      final request = state.requests[key];
      if (request == null || request.retryingAuth || state.endedOn(request)) {
        continue;
      }
      request.connectionGone = true;
      _checkNetworkClose(state);
    }
  }

  void handleEvent(
    NostrMessageRaw nostrMsgRaw,
    RelayConnection connectivity,
    int messageSize,
  ) {
    final requestId = nostrMsgRaw.requestId!;
    final event = nostrMsgRaw.nip01Event!;

    if (inFlight[requestId] == null) {
      Logger.log.w(
        () =>
            "RECEIVED EVENT from ${connectivity.url} for id $requestId, not in flight. Likely data after EOSE on a query",
      );
      return;
    }

    connectivity.stats.incStatsByNewEvent(event, messageSize);

    RequestState? state = inFlight[requestId];
    if (state != null) {
      RelayRequestState? request = state.requests[connectivity.key];
      if (request == null) {
        Logger.log.w(() => "No RelayRequestState found for id $requestId");
        return;
      }

      if (state.networkController.isClosed) {
        // this might happen because relays even after we send a CLOSE subscription.id, they'll still send more events
        Logger.log.t(
          () => "tried to add event to an already closed STREAM ${state.id}",
        );
      } else {
        state.networkController.add(RelayReqEvent(event, connectivity.url));
      }
    }
  }

  /// handles EOSE messages
  void handleEose(List<dynamic> eventJson, RelayConnection relayConnectivity) {
    String id = eventJson[1];
    RequestState? state = inFlight[id];
    if (state == null) return;
    Logger.log.t(
      () =>
          "⛁ received EOSE from ${relayConnectivity.url} for REQ id $id, remaining requests from :${state.requests.keys} kind:${state.requests.values.first.filters.first.kinds}",
    );
    state.requests[relayConnectivity.key]?.receivedEOSE = true;
    if (!state.closeOnEose) return;

    _sendCloseToRelay(relayConnectivity, state.id);
    _checkNetworkClose(state);
    logActive();
  }

  /// handles CLOSED messages for REQ [id]
  void handleClosed(
    String id,
    String? message,
    RelayConnection relayConnectivity,
  ) {
    // Check if this is an auth-required CLOSED message
    if (message != null && message.startsWith("auth-required")) {
      _handleClosedAuthRequired(id, relayConnectivity, message);
      return;
    }

    RequestState? state = inFlight[id];
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
      logActive();
    }
  }

  /// Most slots of [limit] that subscriptions may hold. strfry caps the
  /// database query and the live subscription apart, so a connection full of
  /// subscriptions still answers queries there: the rest stays theirs.
  static int _subscriptionShare(int limit) => limit - limit ~/ 4;

  int _subscriptionsIn(Set<String> slots) =>
      slots.where((id) => inFlight[id]?.isSubscription ?? false).length;

  /// Writes [request] on [connectivity] when a slot is free there, otherwise
  /// queues it until one is. Completes with what kept it from being written
  /// right away.
  Future<RelayFailure?> _admit(
    RelayConnection connectivity,
    RequestState state,
    RelayRequestState request,
  ) {
    // a REQ open there already is not sent twice, nor queued twice
    if (connectivity.holdsSlot(state.id) || _queued.contains(request)) {
      return Future.value();
    }
    // before queueing too: a CLOSED auth-required it still carried would make
    // it look ended while it waits, and dropped from its queue
    request.forgetAnswers();
    final limit = connectivity.subscriptionLimit;
    var heldByShare = false;
    if (limit != null && connectivity.isConnected) {
      final slots = connectivity.heldSlots;
      heldByShare =
          state.isSubscription &&
          _subscriptionsIn(slots) >= _subscriptionShare(limit);
      if (slots.length < limit && !heldByShare) {
        return _write(connectivity, state, request);
      }
    }
    if (heldByShare) {
      Logger.log.w(
        () =>
            "REQ ${state.id} waits on ${connectivity.key}: subscriptions hold "
            "${_subscriptionShare(limit!)} of its $limit slots",
      );
    } else {
      Logger.log.d(
        () => "REQ ${state.id} waits for a slot on ${connectivity.key}",
      );
    }
    _waiting.putIfAbsent(connectivity.key, _Waiting.new).of(state).add((
      order: _queuedSoFar++,
      state: state,
      request: request,
    ));
    _queued.add(request);
    return Future.value();
  }

  /// Writes [request] on [connectivity], where it holds a slot from now on.
  Future<RelayFailure?> _write(
    RelayConnection connectivity,
    RequestState state,
    RelayRequestState request,
  ) async {
    final write = Object();
    connectivity.reservedRequestIds[state.id] = write;
    try {
      await _connections.sendOrThrow(
        connectivity,
        ClientMsg(
          ClientMsgType.kReq,
          id: state.id,
          filters: request.filters,
        ).toJson(),
      );
      return null;
    } on MessageTooLong catch (e) {
      Logger.log.w(() => "REQ ${state.id} not sent to ${request.url}: $e");
      // a replay or a queued REQ has nobody else to report it
      _failRelayRequest(state, request.key, request.filters, e.failure);
      return e.failure;
    } catch (e) {
      Logger.log.w(() => "COULD NOT SEND REQUEST TO ${request.url}:", error: e);
      return RelayFailure(RelayFailureKind.connectionLost, "$e");
    } finally {
      if (identical(connectivity.reservedRequestIds[state.id], write)) {
        connectivity.reservedRequestIds.remove(state.id);
      }
      // a write that did not land frees its slot
      if (!connectivity.holdsSlot(state.id)) admitQueuedOn(connectivity);
    }
  }

  @override
  void admitQueuedOn(RelayConnection connectivity) {
    final waiting = _waiting[connectivity.key];
    final limit = connectivity.subscriptionLimit;
    if (waiting == null || limit == null || !connectivity.isConnected) return;
    final slots = connectivity.heldSlots;
    final share = _subscriptionShare(limit);
    var held = slots.length;
    var subscriptions = _subscriptionsIn(slots);
    while (held < limit) {
      final query = _head(waiting.queries);
      final subscription = subscriptions < share
          ? _head(waiting.subscriptions)
          : null;
      final next = query == null
          ? subscription
          : subscription == null || query.order < subscription.order
          ? query
          : subscription;
      if (next == null) break;
      waiting.of(next.state).removeFirst();
      _queued.remove(next.request);
      if (connectivity.holdsSlot(next.state.id)) continue;
      held++;
      if (next.state.isSubscription) subscriptions++;
      unawaited(_write(connectivity, next.state, next.request));
    }
    if (waiting.isEmpty && identical(_waiting[connectivity.key], waiting)) {
      _waiting.remove(connectivity.key);
    }
  }

  /// The first request of [queue] still waiting, once those that stopped
  /// waiting are dropped.
  _Queued? _head(Queue<_Queued> queue) {
    while (queue.isNotEmpty) {
      final entry = queue.first;
      if (_queued.contains(entry.request) &&
          isStillInFlight(entry.state) &&
          !entry.state.networkController.isClosed &&
          !entry.state.endedOn(entry.request)) {
        return entry;
      }
      queue.removeFirst();
      _queued.remove(entry.request);
    }
    return null;
  }

  void _dropQueue(RelayConnectionKey key) {
    final waiting = _waiting.remove(key);
    if (waiting == null) return;
    for (final entry in [...waiting.queries, ...waiting.subscriptions]) {
      _queued.remove(entry.request);
    }
  }

  /// Marks what the relay itself ended with a CLOSED. It stops counting as open
  /// on that connection, and there is no CLOSE left for us to send.
  void _endRequestOnRelay(
    RelayConnection relayConnectivity,
    String reqId,
    RelayRequestState request,
    String? message,
  ) {
    request.markClosed(message);
    if (relayConnectivity.stats.openRequestIds.remove(reqId)) {
      admitQueuedOn(relayConnectivity);
    }
  }

  /// Whether [state] is still the request tracked under its id. A request
  /// closed while an authentication or a connection was pending must not be
  /// sent afterwards: nothing tracks it anymore, so nothing would ever CLOSE it.
  bool isStillInFlight(RequestState state) =>
      identical(inFlight[state.id], state);

  /// Announces a send path that has yet to work out which connection to use,
  /// so a relay answering meanwhile does not look like the only one this
  /// request ever had. Pair every call with [endPendingConnection].
  void beginPendingConnection(RequestState state) => state.pendingConnections++;

  /// Ends what [beginPendingConnection] announced, and reconsiders closing the
  /// request. A path that gave up without registering anything is the last
  /// thing that can notice: nothing else runs when a connection simply never
  /// opened.
  void endPendingConnection(RequestState state) {
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
    RelayFailure failure,
  ) {
    if (!isStillInFlight(state)) return;
    state.addRequest(key, filters);
    state.requests[key]!.markNotSent(failure);
    _checkNetworkClose(state);
  }

  /// Sends [filters] to [url] for [state], on the connection its [AuthPolicy]
  /// allows. The relay is tracked before this returns, so a request sealed
  /// right after does not end on it.
  ///
  /// Each relay takes one call: [filters] travel in a single REQ, since a
  /// second REQ with the same id would replace the first on the relay.
  Future<void> sendToRelay(
    RequestState state,
    String url,
    List<Filter> filters,
  ) async {
    // a relay an engine handed over late, once the request is over, must not
    // revive it: nothing would ever CLOSE that REQ
    if (!isStillInFlight(state) || state.networkController.isClosed) return;
    final auth = state.auth;
    final key = RelayConnectionKey.forAuth(url, auth);
    if (key == null) {
      final account = (auth as AuthPolicyRequire).account;
      _failRelayRequest(
        state,
        RelayConnectionKey.authenticated(url, account.pubkey),
        filters,
        const RelayFailure(RelayFailureKind.cannotSign),
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
    beginPendingConnection(state);
    try {
      final failure = await _sendTrackedRequest(state, request);
      if (failure != null) {
        _failRelayRequest(state, request.key, request.filters, failure);
      }
    } finally {
      endPendingConnection(state);
    }
  }

  /// Null once sent, otherwise what kept [request] from being sent.
  Future<RelayFailure?> _sendTrackedRequest(
    RequestState state,
    RelayRequestState request,
  ) async {
    if (_connections.blockedRelays.contains(request.url)) {
      Logger.log.w(
        () => "COULD NOT SEND REQUEST TO ${request.url} since relay is blocked",
      );
      return const RelayFailure(RelayFailureKind.blocked);
    }

    final connected = await _connections.reconnectConnection(
      request.key,
      force: false,
      as: state.auth?.account,
      pausing: state,
    );
    // a timeout or a close may have ended the request while the connection
    // was opening: nothing tracks it anymore, so nothing would ever CLOSE what
    // we would send here
    if (!isStillInFlight(state)) {
      return const RelayFailure(RelayFailureKind.requestEnded);
    }
    if (!connected) {
      Logger.log.e(
        () =>
            "COULD NOT SEND REQUEST TO ${request.url} since socket seems to be not open",
      );
      return const RelayFailure(RelayFailureKind.unreachable);
    }
    final relay = _connections.relays[request.key];
    if (relay == null) {
      Logger.log.w(
        () =>
            "COULD NOT SEND REQUEST TO ${request.url}, ${request.key} is gone",
      );
      return const RelayFailure(RelayFailureKind.connectionLost);
    }
    return _admit(relay, state, request);
  }

  /// Sends a CLOSE wherever [state] is still open on a relay, then ends it.
  Future<void> close(RequestState state) async {
    for (final request in state.requests.values) {
      if (_queued.remove(request)) {
        request.markNotSent(
          const RelayFailure(RelayFailureKind.connectionFull),
        );
      }
    }
    for (final relay in _connections.connectedRelays) {
      final request = state.requests[relay.key];
      // a request the relay ended itself, or never got, needs no CLOSE
      if (request == null ||
          state.endedOn(request) ||
          !relay.holdsSlot(state.id)) {
        continue;
      }
      _sendCloseToConnection(relay.key, state.id);
    }

    await state.close();
    if (identical(inFlight[state.id], state)) {
      inFlight.remove(state.id);
    }
  }

  /// Handles CLOSED auth-required.
  ///
  /// A connection is bound to at most one identity, and that binding never
  /// changes. An anonymous connection therefore hands the request over to a
  /// bound one, while a bound connection answers the challenge itself.
  void _handleClosedAuthRequired(
    String reqId,
    RelayConnection relayConnectivity,
    String message,
  ) {
    final state = inFlight[reqId];
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
      final session = _auth.sessionOf(key);
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
      _connections.authenticate(key).then((authenticated) {
        if (!isStillInFlight(state)) {
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
        unawaited(_admit(relayConnectivity, state, request));
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
    beginPendingConnection(state);
    _connections.openConnectionAs(key.url, account).then((bound) {
      try {
        if (!isStillInFlight(state)) {
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
        unawaited(_admit(bound, state, retry));
      } finally {
        endPendingConnection(state);
      }
    });
  }

  /// Account a request authenticates as, null when it must stay unattributable.
  Account? _accountForRequest(RequestState state) =>
      _auth.accountForAuth(state.auth);

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
      _connections.notifyChanged();
      return;
    }

    /// check if relays for this request are still connected
    /// if not ignore it and wait for the ones still alive to finish. A
    /// connection that was dropped entirely counts as gone too, otherwise a
    /// request left on it would wait for a socket nobody will reopen. One that
    /// is retrying its authentication is the exception: its replacement is on
    /// its way and owes it a replay.
    final myNotConnectedRelays = state.requests.keys
        .where((key) => !_connections.isConnectionOpen(key))
        .toList();

    final bool didAllRelaysFinish = state.requests.values.every(
      (element) =>
          !element.retryingAuth &&
          (state.endedOn(element) ||
              myNotConnectedRelays.contains(element.key)),
    );

    if (didAllRelaysFinish) {
      for (final key in myNotConnectedRelays) {
        final request = state.requests[key]!;
        if (!state.endedOn(request)) request.connectionGone = true;
      }
      state.networkController.close();
      _connections.notifyChanged();
    }
  }

  /// sends a close message on the connection the subscription was sent on
  void _sendCloseToConnection(RelayConnectionKey key, String id) {
    RelayConnection? connectivity = _connections.relays[key];
    if (connectivity != null) {
      _sendCloseToRelay(connectivity, id);
    }
  }

  void _sendCloseToRelay(RelayConnection relayConnectivity, String id) {
    try {
      _connections.sendTo(
        relayConnectivity,
        ClientMsg(ClientMsgType.kClose, id: id).toJson(),
      );
    } catch (e) {
      Logger.log.e(() => e);
    }
  }

  void logActive() {
    Map<String?, int> namesMap = {};
    inFlight.forEach((key, state) {
      namesMap[state.name] = (namesMap[state.name] ?? 0) + 1;
    });
    Logger.log.d(
      () => "------------ IN FLIGHT REQUESTS: ${inFlight.length} || $namesMap",
    );
  }

  /// Whether a request still needs the connection behind [key].
  bool hasWorkOn(RelayConnectionKey key) {
    for (final state in inFlight.values) {
      if (state.networkController.isClosed) continue;
      final request = state.requests[key];
      if (request != null &&
          (request.retryingAuth ||
              (!request.receivedClosed &&
                  (state.isSubscription || !request.receivedEOSE)))) {
        return true;
      }
    }
    return false;
  }
}
