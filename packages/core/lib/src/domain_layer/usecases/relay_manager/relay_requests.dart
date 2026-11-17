import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../shared/logger.dart';
import '../../../shared/nips/nip01/client_msg.dart';
import '../../../shared/nips/nip01/nostr_message_raw.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_failure.dart';
import '../../entities/relay_req_event.dart';
import 'auth_session.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';
import 'relay_limits.dart';
import 'req_queue.dart';
import 'request_state.dart';

/// The REQs in flight on a `RelayManager`: sending them, following what each
/// relay answers, replaying them on a new socket and moving them to a bound
/// connection when a relay asks for authentication. Internal to dostr_core.
///
/// A connection carries at most as many REQs as its relay accepts, the
/// others wait in its queue for a slot.
class RelayRequests {
  final RelayConnections _connections;
  final RelayAuth _auth;

  /// holds the state of all in flight requests
  /// key: request Id
  final Map<String, RequestState> inFlight = {};

  late final ReqQueue _queue = ReqQueue(inFlight);

  RelayRequests({
    required RelayConnections connections,
    required RelayAuth auth,
  }) : _connections = connections,
       _auth = auth;

  /// Puts back on [connection] what the socket it replaces still owed us:
  /// its subscriptions, and the queries that never got their EOSE.
  void replayOn(RelayConnection connection) {
    final transport = connection.relayTransport;
    if (transport == null || !transport.isOpen()) {
      return;
    }

    // what waited on the previous socket waits again below, in order
    _queue.drop(connection.key);
    inFlight.forEach((key, state) {
      // by connection, not by relay: replaying a bound request on the
      // anonymous socket gets it refused, and replaying an anonymous one on a
      // bound socket makes it attributable
      final request = state.requests[connection.key];
      if (request != null && request.isReplayable) {
        unawaited(_admit(connection, state, request));
      }
    });
  }

  /// Gives up on the requests that were still waiting for [key] to replay them.
  /// A request the replacement socket took back has stopped retrying by now, so
  /// what is left here is what nothing will send again.
  void endAuthRetriesOn(RelayConnectionKey key) {
    for (final state in inFlight.values.toList()) {
      final request = state.requests[key];
      if (request == null ||
          request.progress != RelayReqProgress.retryingAuth) {
        continue;
      }
      request.endAuthRetry();
      _checkNetworkClose(state);
    }
  }

  /// Gives up on the requests [key] still owed us once nothing will bring that
  /// connection back. They are reported as disconnected right away instead of
  /// waiting for a completion event no relay will send, or for the timeout.
  void endRequestsOn(RelayConnectionKey key) {
    // a request waiting there ends as disconnected too: the connection died,
    // it was not full
    _queue.drop(key);
    for (final state in inFlight.values.toList()) {
      final request = state.requests[key];
      if (request == null ||
          request.isDone ||
          request.progress == RelayReqProgress.retryingAuth) {
        continue;
      }
      request.markGone();
      _checkNetworkClose(state);
    }
  }

  void handleEvent(
    NostrMessageRaw nostrMsgRaw,
    RelayConnection connection,
    int messageSize,
  ) {
    final requestId = nostrMsgRaw.requestId!;
    final event = nostrMsgRaw.nip01Event!;

    if (inFlight[requestId] == null) {
      logger.warning(
        () =>
            "RECEIVED EVENT from ${connection.url} for id $requestId, not in flight. Likely data after EOSE on a query",
      );
      return;
    }

    connection.stats.incStatsByNewEvent(event, messageSize);

    RequestState? state = inFlight[requestId];
    if (state != null) {
      RelayRequestState? request = state.requests[connection.key];
      if (request == null) {
        logger.warning(() => "No RelayRequestState found for id $requestId");
        return;
      }

      if (!request.filters.any((filter) => filter.matches(event))) {
        logger.warning(
          () =>
              "Dropping event ${event.id} from ${connection.url}: no filter of REQ $requestId matches it",
        );
        return;
      }

      if (state.isOver) {
        // this might happen because relays even after we send a CLOSE subscription.id, they'll still send more events
        logger.finest(
          () => "tried to add event to an already closed STREAM ${state.id}",
        );
      } else {
        state.deliver(RelayReqEvent(event, connection.url));
      }
    }
  }

  /// handles EOSE messages
  void handleEose(List<dynamic> eventJson, RelayConnection connection) {
    String id = eventJson[1];
    RequestState? state = inFlight[id];
    if (state == null) return;
    logger.finest(
      () =>
          "⛁ received EOSE from ${connection.url} for REQ id $id, remaining requests from :${state.requests.keys} kind:${state.requests.values.first.filters.first.kinds}",
    );
    state.requests[connection.key]?.markCaughtUp();
    if (!state.closeOnEose) return;

    _sendCloseToRelay(connection, state.id);
    _checkNetworkClose(state);
    logActive();
  }

  /// handles CLOSED messages for REQ [id]
  void handleClosed(String id, String? message, RelayConnection connection) {
    // Check if this is an auth-required CLOSED message
    if (message != null && message.startsWith("auth-required")) {
      _handleClosedAuthRequired(id, connection, message);
      return;
    }

    RequestState? state = inFlight[id];
    if (state != null) {
      logger.finest(
        () =>
            "⛁ received CLOSE from ${connection.url} for REQ id $id, remaining requests from :${state.requests.keys} kind:${state.requests.values.first.filters.first.kinds}",
      );
      RelayRequestState? request = state.requests[connection.key];
      if (request != null) {
        _endRequestOnRelay(connection, id, request, message);
      }

      _checkNetworkClose(state);
      logActive();
    }
  }

  /// Writes [request] on [connection] when a slot is free there, otherwise
  /// queues it until one is.
  Future<void> _admit(
    RelayConnection connection,
    RequestState state,
    RelayRequestState request,
  ) {
    // a REQ open there already is not sent twice, nor queued twice
    if (connection.holdsSlot(state.id) || _queue.contains(request)) {
      return Future.value();
    }
    // before queueing too: a CLOSED auth-required it still carried would make
    // it look ended while it waits, and dropped from its queue
    request.forgetAnswers();
    if (_queue.holdBack(connection, state, request)) return Future.value();
    return _write(connection, state, request);
  }

  /// Writes [request] on [connection], where it holds a slot from now on.
  ///
  /// A write the socket went away under is left to the connection: it replays
  /// the request once it is back, or gives it up as disconnected.
  Future<void> _write(
    RelayConnection connection,
    RequestState state,
    RelayRequestState request,
  ) async {
    final write = Object();
    connection.reservedRequestIds[state.id] = write;
    try {
      await _connections.sendOrThrow(
        connection,
        ClientMsg(
          ClientMsgType.kReq,
          id: state.id,
          filters: request.filters,
        ).toJson(),
      );
    } on MessageTooLong catch (e) {
      logger.warning(() => "REQ ${state.id} not sent to ${request.url}: $e");
      _failRelayRequest(state, request.key, request.filters, e.failure);
    } catch (e) {
      logger.warning(() => "COULD NOT SEND REQUEST TO ${request.url}:", e);
    } finally {
      if (identical(connection.reservedRequestIds[state.id], write)) {
        connection.reservedRequestIds.remove(state.id);
      }
      // a write that did not land frees its slot
      if (!connection.holdsSlot(state.id)) admitQueuedOn(connection);
    }
  }

  void admitQueuedOn(RelayConnection connection) => _queue.admit(
    connection,
    (state, request) => unawaited(_write(connection, state, request)),
  );

  /// Marks what the relay itself ended with a CLOSED. It stops counting as open
  /// on that connection, and there is no CLOSE left for us to send.
  void _endRequestOnRelay(
    RelayConnection connection,
    String reqId,
    RelayRequestState request,
    String? message,
  ) {
    request.markClosed(message);
    if (connection.stats.openRequestIds.remove(reqId)) {
      admitQueuedOn(connection);
    }
  }

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

  /// Runs [work], a send path that has yet to work out which connection to
  /// use, between [beginPendingConnection] and [endPendingConnection].
  Future<void> _whilePending(
    RequestState state,
    Future<void> Function() work,
  ) async {
    beginPendingConnection(state);
    try {
      await work();
    } finally {
      endPendingConnection(state);
    }
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
    if (state.isOver) return;
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
    RelayUrl url,
    List<Filter> filters,
  ) async {
    // a relay handed over late, once the request is over, must not revive it:
    // nothing would ever CLOSE that REQ
    if (state.isOver) return;
    final auth = state.auth;
    final key = RelayConnectionKey.forAuth(url, auth);
    if (key == null) {
      final account = (auth as AuthPolicyRequire).signer;
      _failRelayRequest(
        state,
        RelayConnectionKey.authenticated(url, account.publicKey),
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
  ///
  /// A connection that is still opening is not one that is gone, and
  /// [_checkNetworkClose] cannot tell them apart on its own.
  Future<void> _sendTracked(RequestState state, RelayRequestState request) =>
      _whilePending(state, () async {
        final failure = await _sendTrackedRequest(state, request);
        if (failure != null) {
          _failRelayRequest(state, request.key, request.filters, failure);
        }
      });

  /// What kept [request] from being sent, null once it is on its way: written,
  /// queued for a slot, or left to a connection that replays it once back.
  Future<RelayFailure?> _sendTrackedRequest(
    RequestState state,
    RelayRequestState request,
  ) async {
    final opening = await _connections.ensureOpen(
      request.key,
      as: state.auth?.signer,
      pausing: state,
    );
    // a timeout or a close may have ended the request while the connection
    // was opening: nothing would ever CLOSE what we would send here
    if (state.isOver) {
      return const RelayFailure(RelayFailureKind.requestEnded);
    }
    switch (opening) {
      case Opened(:final connection):
        await _admit(connection, state, request);
      case ComingBack():
        break;
      case NotOpened(:final failure):
        logger.warning(
          () => "COULD NOT SEND REQUEST TO ${request.url}: $failure",
        );
        return failure;
    }
    return null;
  }

  /// Whether the `RelayManager` was disposed.
  bool get disposed => _connections.disposed;

  /// Ends every request in flight, see [close].
  Future<void> closeAll() =>
      Future.wait([for (final state in inFlight.values.toList()) close(state)]);

  /// Sends a CLOSE wherever [state] is still open on a relay, then ends it.
  Future<void> close(RequestState state) async {
    for (final request in state.requests.values) {
      if (_queue.remove(request)) {
        request.markNotSent(
          const RelayFailure(RelayFailureKind.connectionFull),
        );
      }
    }
    for (final relay in _connections.connectedRelays) {
      final request = state.requests[relay.key];
      // a request the relay ended itself, or never got, needs no CLOSE
      if (request == null || request.isDone || !relay.holdsSlot(state.id)) {
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
    RelayConnection connection,
    String message,
  ) {
    final state = inFlight[reqId];
    if (state == null) {
      logger.warning(
        () => "Received CLOSED auth-required for unknown request $reqId",
      );
      return;
    }

    final key = connection.key;
    final request = state.requests[key];
    if (request == null) {
      logger.warning(
        () => "Received CLOSED auth-required but no request state for $key",
      );
      return;
    }

    // whatever we do next, the relay just closed this one on this connection
    _endRequestOnRelay(connection, reqId, request, message);
    if (request.progress != RelayReqProgress.closed) {
      _checkNetworkClose(state);
      return;
    }

    if (!key.isAnonymous) {
      final session = _auth.sessionOf(connection);
      if (session.authenticated) {
        // the relay refused us while we were authenticated as the only identity
        // this connection may ever assume, so there is nothing left to try
        logger.warning(() => "REQ $reqId refused on authenticated $key");
        _checkNetworkClose(state);
        return;
      }

      logger.fine(() => "Authenticating $key to satisfy REQ $reqId");
      request.markRetryingAuth();
      unawaited(_authenticateAndRetry(state, connection, request, session));
      return;
    }

    final account = _accountForRequest(state);
    if (account == null) {
      logger.warning(
        () => "Cannot satisfy auth-required for REQ $reqId on $key",
      );
      _checkNetworkClose(state);
      return;
    }

    final target = RelayConnectionKey.authenticated(key.url, account.publicKey);
    state.addRequest(target, request.filters);

    logger.fine(
      () => "AUTH required for REQ $reqId on $key, retrying on $target",
    );

    unawaited(
      _whilePending(state, () => _retryOnBound(state, target, account)),
    );
  }

  /// Answers the challenge of the bound [connection] that refused [request],
  /// then sends it there again.
  Future<void> _authenticateAndRetry(
    RequestState state,
    RelayConnection connection,
    RelayRequestState request,
    AuthSession session,
  ) async {
    final bool authenticated;
    state.pauseTimeout();
    try {
      authenticated = await _connections.authenticate(connection.key);
    } finally {
      state.resumeTimeout();
    }
    if (state.isOver) return;
    if (!authenticated) {
      // an authentication that died with its socket is not a refusal: stay on
      // the retry so the replacement replays the request
      if (!session.ended) request.endAuthRetry();
      _checkNetworkClose(state);
      return;
    }
    await _admit(connection, state, request);
  }

  /// Sends [state] again on the connection to [target], bound to [account],
  /// after an anonymous one refused it.
  Future<void> _retryOnBound(
    RequestState state,
    RelayConnectionKey target,
    NostrSigner account,
  ) async {
    final Opening opening;
    state.pauseTimeout();
    try {
      opening = await _connections.ensureOpen(target, as: account);
    } finally {
      state.resumeTimeout();
    }
    final retry = state.requests[target];
    if (state.isOver || retry == null) return;
    switch (opening) {
      case Opened(:final connection):
        // sent without waiting for the AUTH: a relay that only challenges on
        // demand needs this request as the trigger, and the refusal that may
        // follow lands on the bound branch of _handleClosedAuthRequired
        unawaited(_admit(connection, state, retry));
      case ComingBack():
        break;
      case NotOpened():
        retry.markClosed(
          "auth-required: no authenticated connection could be opened",
        );
    }
  }

  /// Account a request authenticates as, null when it must stay unattributable.
  NostrSigner? _accountForRequest(RequestState state) =>
      _auth.accountForAuth(state.auth);

  void _checkNetworkClose(RequestState state) {
    // a send path is still working out which connection to use, so the relays
    // registered so far are not all this request will ever have
    if (state.pendingConnections > 0) {
      return;
    }
    if (state.didAllRequestsFinish) {
      state.finish();
      return;
    }

    // a connection nobody will bring back owes nothing more, so the request
    // does not wait for it. One retrying its authentication or coming back
    // still owes a replay.
    final owed = state.requests.values.where((request) => !request.isDone);
    if (owed.any(
      (request) =>
          request.progress == RelayReqProgress.retryingAuth ||
          !_connections.isGone(request.key),
    )) {
      return;
    }
    for (final request in owed.toList()) {
      request.markGone();
    }
    state.finish();
  }

  /// sends a close message on the connection the subscription was sent on
  void _sendCloseToConnection(RelayConnectionKey key, String id) {
    RelayConnection? connection = _connections.relays[key];
    if (connection != null) {
      _sendCloseToRelay(connection, id);
    }
  }

  void _sendCloseToRelay(RelayConnection connection, String id) {
    try {
      _connections.sendTo(
        connection,
        ClientMsg(ClientMsgType.kClose, id: id).toJson(),
      );
    } catch (e) {
      logger.severe(() => e);
    }
  }

  void logActive() {
    Map<String?, int> namesMap = {};
    inFlight.forEach((key, state) {
      namesMap[state.name] = (namesMap[state.name] ?? 0) + 1;
    });
    logger.fine(
      () => "------------ IN FLIGHT REQUESTS: ${inFlight.length} || $namesMap",
    );
  }

  /// Whether a request still needs the connection behind [key].
  bool hasWorkOn(RelayConnectionKey key) {
    for (final state in inFlight.values) {
      if (state.isOver) continue;
      final request = state.requests[key];
      if (request != null && !request.isDone) return true;
    }
    return false;
  }
}
