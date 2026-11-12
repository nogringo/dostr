import 'dart:async';

import '../config/relay_defaults.dart';
import '../domain_layer/entities/timeout_pausable.dart';
import 'package:ndk_signer/ndk_signer.dart';
import '../domain_layer/entities/broadcast_state.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import '../domain_layer/entities/relay_connection_key.dart';
import '../domain_layer/entities/relay_failure.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'logger/logger.dart';
import 'broadcast_state.dart';
import 'client_msg.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';

/// The EVENTs in flight on a `RelayManager`: sending them, routing each OK to
/// the broadcasts waiting on it and moving them to a bound connection when a
/// relay asks for authentication. Internal to ndk_core.
class RelayBroadcasts {
  final RelayConnections _connections;
  final RelayAuth _auth;

  /// hold state information for a broadcast
  /// key: event Id
  /// value: one state per broadcast call, the same event can be in flight
  /// several times at once
  final Map<String, List<BroadcastState>> inFlight = {};

  RelayBroadcasts({
    required RelayConnections connections,
    required RelayAuth auth,
  }) : _connections = connections,
       _auth = auth;

  /// Whether a broadcast of [eventId] is still waiting on its relays.
  bool isBroadcasting(String eventId) => inFlight.containsKey(eventId);

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
  void _failBroadcast(
    BroadcastState broadcastState,
    String relay,
    RelayFailure failure,
  ) {
    if (broadcastState.networkController.isClosed) {
      Logger.log.w(
        () =>
            "Ignoring late failed broadcast for ${broadcastState.event?.id} on $relay because the broadcast controller is already closed",
      );
      return;
    }

    broadcastState.networkController.add(
      RelayBroadcastResponse(relayUrl: relay, failure: failure),
    );
  }

  /// Tracks [state] as a broadcast of [eventId] until it is done, so the OK of
  /// the relays reach it.
  void track(String eventId, BroadcastState state) {
    inFlight.putIfAbsent(eventId, () => []).add(state);
    void untrack() {
      final states = inFlight[eventId];
      if (states == null) return;
      states.remove(state);
      if (states.isEmpty) inFlight.remove(eventId);
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
  Future<void> publishToRelay(
    BroadcastState state,
    String url,
    Nip01Event event, {
    Duration connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
    Future<String?> Function()? veto,
  }) async {
    _registerRelayBroadcast(
      broadcastState: state,
      eventToPublish: event,
      relayUrl: url,
    );
    try {
      final (:relay, :failure) = await _connectionForBroadcast(
        url,
        state.auth,
        connectTimeout: connectTimeout,
        pausing: state,
      );
      if (relay == null) {
        _failBroadcast(
          state,
          url,
          failure ?? const RelayFailure(RelayFailureKind.unreachable),
        );
        return;
      }
      final String? vetoed;
      try {
        vetoed = await veto?.call();
      } catch (error) {
        _failBroadcast(
          state,
          url,
          RelayFailure(RelayFailureKind.vetoed, "$error"),
        );
        return;
      }
      if (vetoed != null) {
        _failBroadcast(
          state,
          url,
          RelayFailure(RelayFailureKind.vetoed, vetoed),
        );
        return;
      }
      await _connections.sendOrThrow(
        relay,
        ClientMsg(ClientMsgType.kEvent, event: event).toJson(),
      );
    } on MessageTooLong catch (error) {
      _failBroadcast(state, url, error.failure);
    } catch (error) {
      _failBroadcast(
        state,
        url,
        RelayFailure(RelayFailureKind.connectionLost, "$error"),
      );
    }
  }

  /// The connection a broadcast under [auth] must go out on towards [url],
  /// opening it when it is not there yet, or why nothing may be sent.
  ///
  /// Owns the connecting too: a broadcast that requires an identity must not
  /// even open the anonymous connection, because a socket we opened is one the
  /// relay saw, whether or not anything was sent on it.
  Future<({RelayConnection? relay, RelayFailure? failure})>
  _connectionForBroadcast(
    String url,
    AuthPolicy? auth, {
    Duration connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
    TimeoutPausable? pausing,
  }) async {
    if (auth is AuthPolicyRequire) {
      if (!auth.account.signer.canSign()) {
        Logger.log.w(
          () => "Broadcast requires ${auth.account.pubkey}, which cannot sign",
        );
        return (
          relay: null,
          failure: const RelayFailure(RelayFailureKind.cannotSign),
        );
      }
      final bound = await _connections.openConnectionAs(
        url,
        auth.account,
        connectTimeout: connectTimeout,
        pausing: pausing,
      );
      return (
        relay: bound,
        failure: bound == null
            ? const RelayFailure(RelayFailureKind.noBoundConnection)
            : null,
      );
    }

    if (!_connections.isRelayConnected(url)) {
      final result = await _connections.connectRelay(
        dirtyUrl: url,
        connectTimeout: connectTimeout,
      );
      if (!result.connected) {
        Logger.log.w(() => "Could not connect to $url: ${result.failure}");
        return (relay: null, failure: result.failure);
      }
    }
    return (relay: _connections.getRelayConnectivity(url), failure: null);
  }

  /// A relay answers every EVENT it receives, and the same event can be in
  /// flight in several broadcasts. An acceptance means the relay holds the
  /// event, so it answers all of them; a refusal answers a single EVENT.
  void routeOk(
    String eventId,
    RelayConnection relayConnectivity,
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

    // not an answer yet: each broadcast retries under its own auth policy,
    // unless the relay refused the identity this connection already proved
    if (!success &&
        msg.startsWith("auth-required") &&
        !_auth.isAuthenticated(relayConnectivity.key)) {
      for (final broadcastState in waiting) {
        _handleBroadcastAuthRequired(broadcastState, relayConnectivity, msg);
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
    final states = inFlight[eventId] ?? const [];
    return states
        .where(
          (state) =>
              !state.networkController.isClosed &&
              state.broadcasts.values.any(
                (response) =>
                    cleanRelayUrl(response.relayUrl) == relayUrl &&
                    !response.okReceived &&
                    response.failure == null,
              ),
        )
        .toList();
  }

  /// Handles OK auth-required for a broadcast by moving the retry onto an
  /// account-bound connection, authenticating it once, and re-sending EVENT.
  /// Concurrent broadcasts share [RelayConnections.authenticate], avoiding
  /// duplicate AUTH events whose identical ids used to overwrite each other's
  /// callbacks.
  void _handleBroadcastAuthRequired(
    BroadcastState broadcastState,
    RelayConnection relayConnectivity,
    String refusal,
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

    final resolved = _auth.accountForBroadcast(
      broadcastState.auth,
      eventToResend,
    );

    if (resolved == null) {
      Logger.log.w(
        () =>
            "Cannot satisfy auth-required for broadcast $eventId on $relayUrl",
      );
      _failBroadcast(
        broadcastState,
        relayUrl,
        RelayFailure(RelayFailureKind.identityNotAllowed, refusal),
      );
      return;
    }
    final account = resolved;

    final boundKey = RelayConnectionKey.authenticated(relayUrl, account.pubkey);

    Future<void> retryOnBoundConnection() async {
      try {
        final bound = await _connections.openConnectionAs(
          relayUrl,
          account,
          pausing: broadcastState,
        );
        if (broadcastState.networkController.isClosed) {
          return;
        }
        if (bound == null) {
          _failBroadcast(
            broadcastState,
            relayUrl,
            const RelayFailure(RelayFailureKind.noBoundConnection),
          );
          return;
        }

        // Some relays challenge immediately; others only after seeing EVENT on
        // the bound socket. Trigger the latter, then the next auth-required OK
        // enters this method with the bound key and authenticates below.
        if (relayConnectivity.key != boundKey &&
            !_auth.isAuthenticated(boundKey)) {
          await _connections.sendOrThrow(
            bound,
            ClientMsg(ClientMsgType.kEvent, event: eventToResend).toJson(),
          );
          return;
        }

        final accepted = await _connections.authenticate(boundKey);
        if (broadcastState.networkController.isClosed) {
          return;
        }
        if (!accepted) {
          _failBroadcast(
            broadcastState,
            relayUrl,
            const RelayFailure(RelayFailureKind.authenticationFailed),
          );
          return;
        }
        await _connections.sendOrThrow(
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
          _failBroadcast(
            broadcastState,
            relayUrl,
            error is MessageTooLong
                ? error.failure
                : RelayFailure(RelayFailureKind.connectionLost, "$error"),
          );
        }
      } finally {
        broadcastState.retryingAuth.remove(relayUrl);
      }
    }

    broadcastState.retryingAuth.add(relayUrl);
    unawaited(retryOnBoundConnection());
  }

  /// Whether a broadcast still waits on the relay behind [key]. Broadcasts
  /// track relay urls rather than identities, so every connection to that
  /// relay counts.
  bool hasWorkOn(RelayConnectionKey key) => inFlight.values
      .expand((states) => states)
      .any(
        (state) =>
            !state.networkController.isClosed &&
            state.broadcasts.keys.any((url) => cleanRelayUrl(url) == key.url),
      );
}
