import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../auth/auth_session.dart';
import '../auth/relay_auth.dart';
import '../connections/relay_connection.dart';
import '../connections/relay_connection_key.dart';
import '../connections/relay_connections.dart';
import '../connections/relay_limits.dart';
import '../helpers/logger.dart';
import '../messages/client_messages.dart';
import '../messages/nostr_message_raw.dart';
import '../relay_failure.dart';
import 'relay_req_event.dart';
import 'req_queue.dart';
import 'request_state.dart';

/// The REQs in flight on a `RelayManager`. Internal to dostr_core.
///
/// It sends them, follows what each relay answers, replays them on a new
/// socket, and moves them to a bound connection when a relay asks for
/// authentication. A connection carries at most as many REQs as its relay
/// accepts. The others wait in its queue for a slot.
class RelayRequests {
  final RelayConnections _connections;
  final RelayAuth _auth;

  /// The requests in flight, by subscription id.
  final Map<String, RequestState> inFlight = {};

  late final ReqQueue _queue = ReqQueue(inFlight);

  RelayRequests({
    required RelayConnections connections,
    required RelayAuth auth,
  }) : _connections = connections,
       _auth = auth;

  /// Whether the `RelayManager` was disposed.
  bool get disposed => _connections.disposed;

  /// Sends [state] to each of [relays], on the connection its [AuthPolicy]
  /// allows there.
  ///
  /// Every relay is tracked before the first one is sent to, so an early
  /// answer cannot end the request while the others are still being added.
  /// Each relay gets its filters in a single REQ: a second REQ with the same
  /// id would replace the first one on the relay.
  void start(RequestState state, Map<RelayUrl, List<Filter>> relays) {
    inFlight[state.id] = state;
    final tracked = [
      for (final MapEntry(key: url, value: filters) in relays.entries)
        ?_track(state, url, filters),
    ];
    for (final request in tracked) {
      unawaited(_send(state, request));
    }
    _finishIfDone(state);
  }

  /// Tracks [state] on the connection to [url] that its [AuthPolicy] allows.
  /// Returns null, with the relay marked notSent, when no connection can
  /// carry it.
  RelayRequestState? _track(
    RequestState state,
    RelayUrl url,
    List<Filter> filters,
  ) {
    final auth = state.auth;
    final key = RelayConnectionKey.forAuth(url, auth);
    if (key != null) return state.addRequest(key, filters);
    final signer = (auth as AuthPolicyRequire).signer;
    state
        .addRequest(
          RelayConnectionKey.authenticated(url, signer.publicKey),
          filters,
        )
        .markNotSent(const RelayFailure(RelayFailureKind.cannotSign));
    return null;
  }

  /// Sends [request] once its connection is open, or marks it notSent.
  Future<void> _send(RequestState state, RelayRequestState request) async {
    final failure = await _sendOnceOpen(state, request);
    if (failure != null) {
      _failRelayRequest(state, request, failure);
    } else {
      _finishIfDone(state);
    }
  }

  /// What kept [request] from being sent. Null once it is on its way.
  Future<RelayFailure?> _sendOnceOpen(
    RequestState state,
    RelayRequestState request,
  ) async {
    final opening = await _connections.ensureOpen(
      request.key,
      as: state.auth?.signer,
      pausing: state,
    );
    // nothing would ever CLOSE a REQ sent after the request ended
    if (state.isOver) {
      return const RelayFailure(RelayFailureKind.requestEnded);
    }
    switch (opening) {
      case Opened(:final connection):
        await _admit(connection, state, request);
      case ComingBack():
        request.markOnItsWay();
      case NotOpened(:final failure):
        logger.fine(
          () => "REQ ${state.id} not sent to ${request.url}: $failure",
        );
        return failure;
    }
    return null;
  }

  /// Marks [request] notSent because of [failure], unless [state] is over.
  void _failRelayRequest(
    RequestState state,
    RelayRequestState request,
    RelayFailure failure,
  ) {
    if (state.isOver) return;
    request.markNotSent(failure);
    _finishIfDone(state);
  }

  /// Writes [request] on [connection] when a slot is free there. Otherwise it
  /// waits in the queue for one.
  Future<void> _admit(
    RelayConnection connection,
    RequestState state,
    RelayRequestState request,
  ) {
    if (connection.slots.holds(state.id) || _queue.contains(request)) {
      return Future.value();
    }
    // before queueing: a CLOSED auth-required it still carried would make it
    // look ended, and the queue would drop it
    request.markOnItsWay();
    if (_queue.holdBack(connection, state, request)) return Future.value();
    return _write(connection, state, request);
  }

  /// Writes [request] on [connection], where it holds a slot from now on.
  ///
  /// When the socket goes away during the write, the connection replays the
  /// request once it is back, or gives it up as disconnected.
  Future<void> _write(
    RelayConnection connection,
    RequestState state,
    RelayRequestState request,
  ) async {
    final write = connection.slots.reserve(state.id);
    try {
      await _connections.sendOrThrow(
        connection,
        reqMessage(state.id, request.filters),
      );
    } on MessageTooLong catch (e) {
      logger.warning(() => "REQ ${state.id} not sent to ${request.url}: $e");
      _failRelayRequest(state, request, e.failure);
    } catch (e) {
      logger.fine(() => "REQ ${state.id} not sent to ${request.url}", e);
    } finally {
      connection.slots.release(state.id, write);
      // a write that did not land frees its slot
      if (!connection.slots.holds(state.id)) admitQueuedOn(connection);
    }
  }

  void admitQueuedOn(RelayConnection connection) => _queue.admit(
    connection,
    (state, request) => unawaited(_write(connection, state, request)),
  );

  /// Sends again on [connection] what the socket it replaces still owed: its
  /// subscriptions, and the queries that got no EOSE.
  void replayOn(RelayConnection connection) {
    if (connection.isConnected) {
      // what waited on the previous socket waits again below, in order
      _queue.drop(connection.key);
      inFlight.forEach((id, state) {
        // by connection, not by relay: an anonymous socket refuses a bound
        // request, and a bound socket makes an anonymous one attributable
        final request = state.requests[connection.key];
        if (request != null && request.isReplayable) {
          unawaited(_admit(connection, state, request));
        }
      });
    }
    // a request still retrying here was not replayed: nothing will send it
    _endAuthRetriesOn(connection.key);
  }

  /// Gives up on what [key] still owed, once nothing will bring that
  /// connection back.
  ///
  /// Its requests end as disconnected right away, rather than waiting for an
  /// answer no relay will send, or for their timeout.
  void endRequestsOn(RelayConnectionKey key) {
    // a request waiting in the queue there ends as disconnected too: the
    // connection died, it was not full
    _queue.drop(key);
    for (final state in inFlight.values.toList()) {
      final request = state.requests[key];
      if (request == null || request.isDone) continue;
      request
        ..endAuthRetry()
        ..markGone();
      _finishIfDone(state);
    }
  }

  void _endAuthRetriesOn(RelayConnectionKey key) {
    for (final state in inFlight.values.toList()) {
      final request = state.requests[key];
      if (request == null ||
          request.progress != RelayReqProgress.retryingAuth) {
        continue;
      }
      request.endAuthRetry();
      _finishIfDone(state);
    }
  }

  void handleEvent(NostrMessageRaw nostrMsgRaw, RelayConnection connection) {
    final requestId = nostrMsgRaw.requestId!;
    final event = nostrMsgRaw.nip01Event!;

    final state = inFlight[requestId];
    if (state == null) {
      logger.fine(
        () =>
            "EVENT from ${connection.url} for $requestId, which is not in flight",
      );
      return;
    }

    final request = state.requests[connection.key];
    if (request == null) {
      logger.fine(
        () =>
            "EVENT from ${connection.url} for $requestId, which was not sent on ${connection.key}",
      );
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
      // relays keep sending for a while after our CLOSE
      logger.finest(
        () => "EVENT from ${connection.url} for $requestId, which is over",
      );
    } else {
      state.deliver(RelayReqEvent(event, connection.url));
    }
  }

  /// A query ends where it got its EOSE. A subscription goes on.
  void handleEose(List<dynamic> eventJson, RelayConnection connection) {
    String id = eventJson[1];
    RequestState? state = inFlight[id];
    if (state == null) return;
    state.requests[connection.key]?.markCaughtUp();
    if (!state.closeOnEose) return;

    _sendCloseToRelay(connection, state.id);
    _finishIfDone(state);
    logActive();
  }

  /// Handles a CLOSED for the REQ [id].
  void handleClosed(String id, String? message, RelayConnection connection) {
    if (message != null && message.startsWith("auth-required")) {
      _handleClosedAuthRequired(id, connection, message);
      return;
    }

    RequestState? state = inFlight[id];
    if (state != null) {
      RelayRequestState? request = state.requests[connection.key];
      if (request != null) {
        _endRequestOnRelay(connection, id, request, message);
      }

      _finishIfDone(state);
      logActive();
    }
  }

  /// Marks what the relay ended with a CLOSED. It no longer holds a slot on
  /// that connection, and needs no CLOSE from us.
  void _endRequestOnRelay(
    RelayConnection connection,
    String reqId,
    RelayRequestState request,
    String? message,
  ) {
    request.markClosed(message);
    _freeSlot(connection, reqId);
  }

  /// Frees the slot of the REQ [reqId], which the relay ended on [connection].
  void _freeSlot(RelayConnection connection, String reqId) {
    if (connection.slots.ended(reqId)) {
      admitQueuedOn(connection);
    }
  }

  /// Ends every request in flight, see [close].
  Future<void> closeAll() =>
      Future.wait([for (final state in inFlight.values.toList()) close(state)]);

  /// Sends a CLOSE wherever [state] is still open on a relay, then ends it.
  Future<void> close(RequestState state) async {
    state.cancel();
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
      if (request == null || request.isDone || !relay.slots.holds(state.id)) {
        continue;
      }
      _sendCloseToConnection(relay.key, state.id);
    }

    await state.close();
    if (identical(inFlight[state.id], state)) {
      inFlight.remove(state.id);
    }
  }

  /// Handles a CLOSED auth-required.
  ///
  /// A connection is bound to at most one identity, for good. An anonymous
  /// connection therefore hands the request over to a bound one, while a bound
  /// connection answers the challenge itself.
  void _handleClosedAuthRequired(
    String reqId,
    RelayConnection connection,
    String message,
  ) {
    final state = inFlight[reqId];
    if (state == null) {
      logger.fine(
        () => "CLOSED auth-required for $reqId, which is not in flight",
      );
      return;
    }

    final key = connection.key;
    final request = state.requests[key];
    if (request == null) {
      logger.fine(
        () => "CLOSED auth-required for $reqId, which was not sent on $key",
      );
      return;
    }

    _freeSlot(connection, reqId);
    if (!_retryAuth(state, connection, request, message)) {
      request.markClosed(message);
      _finishIfDone(state);
    }
  }

  /// Moves [request] on after [connection] refused it with [refusal] for want
  /// of an identity, and says whether it did. It moves before it is marked
  /// refused, so its relay never shows as closed on the way.
  bool _retryAuth(
    RequestState state,
    RelayConnection connection,
    RelayRequestState request,
    String refusal,
  ) {
    if (request.isDone) return false;
    final key = connection.key;
    if (!key.isAnonymous) {
      final session = _auth.sessionOf(connection);
      if (session.authenticated) {
        // refused while authenticated as the only identity this connection
        // may ever take: there is nothing left to try
        logger.fine(() => "REQ ${state.id} refused on authenticated $key");
        return false;
      }

      logger.fine(() => "Authenticating $key to satisfy REQ ${state.id}");
      request.markRetryingAuth(refusal);
      unawaited(_authenticateAndRetry(state, connection, request, session));
      return true;
    }

    final account = _auth.accountForAuth(state.auth);
    if (account == null) {
      logger.fine(
        () => "No identity to answer auth-required for REQ ${state.id} on $key",
      );
      return false;
    }

    final target = RelayConnectionKey.authenticated(key.url, account.publicKey);
    final retry = state.addRequest(target, request.filters);
    request.markClosed(refusal);

    logger.fine(
      () => "AUTH required for REQ ${state.id} on $key, retrying on $target",
    );

    unawaited(_retryOnBound(state, retry, account, refusal: refusal));
    return true;
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
      // an authentication that died with its socket is not a refusal: the
      // request stays on its retry, and the new socket replays it
      if (!session.ended) request.endAuthRetry();
      _finishIfDone(state);
      return;
    }
    await _admit(connection, state, request);
  }

  /// Sends [retry] on its connection, bound to [account], after an anonymous
  /// one refused the request with [refusal].
  Future<void> _retryOnBound(
    RequestState state,
    RelayRequestState retry,
    NostrSigner account, {
    required String refusal,
  }) async {
    try {
      final Opening opening;
      state.pauseTimeout();
      try {
        opening = await _connections.ensureOpen(retry.key, as: account);
      } finally {
        state.resumeTimeout();
      }
      if (state.isOver) return;
      switch (opening) {
        case Opened(:final connection):
          // sent without waiting for the AUTH: a relay that only challenges on
          // demand needs this REQ to do so, and the refusal that may follow
          // lands on the bound branch of _handleClosedAuthRequired
          unawaited(_admit(connection, state, retry));
        case ComingBack():
          retry.markOnItsWay();
        case NotOpened():
          retry.markClosed(refusal);
      }
    } finally {
      _finishIfDone(state);
    }
  }

  /// Ends [state] once no relay owes it anything.
  ///
  /// A relay whose connection nothing will bring back owes nothing more. One
  /// whose connection is opening, coming back, or retrying its authentication
  /// still does.
  void _finishIfDone(RequestState state) {
    if (state.didAllRequestsFinish) {
      state.finish();
      return;
    }
    final owed = state.requests.values.where((request) => !request.isDone);
    if (owed.any(
      (request) => request.isBeingSent || !_connections.isGone(request.key),
    )) {
      return;
    }
    for (final request in owed.toList()) {
      request.markGone();
    }
    state.finish();
  }

  void _sendCloseToConnection(RelayConnectionKey key, String id) {
    RelayConnection? connection = _connections.relays[key];
    if (connection != null) {
      _sendCloseToRelay(connection, id);
    }
  }

  void _sendCloseToRelay(RelayConnection connection, String id) =>
      _connections.sendTo(connection, closeMessage(id));

  void logActive() {
    Map<String?, int> namesMap = {};
    inFlight.forEach((key, state) {
      namesMap[state.name] = (namesMap[state.name] ?? 0) + 1;
    });
    logger.fine(() => "${inFlight.length} REQs in flight, by name: $namesMap");
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
