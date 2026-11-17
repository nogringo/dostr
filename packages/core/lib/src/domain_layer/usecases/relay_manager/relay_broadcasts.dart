import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../config/relay_defaults.dart';
import '../../../shared/logger.dart';
import '../../../shared/nips/nip01/client_msg.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_failure.dart';
import '../../entities/relay_publish_outcome.dart';
import 'broadcast_state.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';
import 'relay_limits.dart';

/// The EVENTs in flight on a `RelayManager`: sending them, routing each OK to
/// the broadcasts waiting on it and moving them to a bound connection when a
/// relay asks for authentication. Internal to dostr_core.
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
    required RelayUrl relayUrl,
    required Nip01Event eventToPublish,
  }) {
    // Store the event for potential retries on auth-required
    broadcastState.event ??= eventToPublish;

    // new tracking
    if (broadcastState.broadcasts[relayUrl] == null) {
      broadcastState.broadcasts[relayUrl] = const RelayPublishOutcome();
    } else {
      // do not overwrite
      logger.warning(
        () =>
            "_registerRelayBroadcast: relay broadcast already registered for ${eventToPublish.id} $relayUrl, skipping",
      );
    }
  }

  /// use this to signal a failed broadcast
  void _failBroadcast(
    BroadcastState broadcastState,
    RelayUrl relay,
    RelayFailure failure,
  ) {
    if (broadcastState.networkController.isClosed) {
      logger.warning(
        () =>
            "Ignoring late failed broadcast for ${broadcastState.event?.id} on $relay because the broadcast controller is already closed",
      );
      return;
    }

    broadcastState.networkController.add((
      url: relay,
      outcome: RelayPublishOutcome(failure: failure),
    ));
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
    RelayUrl url,
    Nip01Event event, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
    Future<String?> Function()? veto,
  }) async {
    _registerRelayBroadcast(
      broadcastState: state,
      eventToPublish: event,
      relayUrl: url,
    );
    try {
      final (:relay, :failure) = await _connectionForBroadcast(
        state,
        url,
        connectTimeout: connectTimeout,
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

  /// The connection [state] must go out on towards [url], opening it when it
  /// is not there yet, or why nothing may be sent.
  ///
  /// Owns the connecting too: a broadcast that requires an identity must not
  /// even open the anonymous connection, because a socket we opened is one the
  /// relay saw, whether or not anything was sent on it.
  Future<({RelayConnection? relay, RelayFailure? failure})>
  _connectionForBroadcast(
    BroadcastState state,
    RelayUrl url, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    final auth = state.auth;
    final key = RelayConnectionKey.forAuth(url, auth);
    if (key == null) {
      logger.warning(
        () =>
            "Broadcast requires ${auth?.signer?.publicKey}, which cannot sign",
      );
      return (
        relay: null,
        failure: const RelayFailure(RelayFailureKind.cannotSign),
      );
    }
    return _open(state, key, as: auth?.signer, connectTimeout: connectTimeout);
  }

  /// The connection behind [key] once it is open, or why [state] cannot go
  /// out on it. One that is coming back is waited for while [state] lasts.
  ///
  /// A relay tried a moment ago is tried again: an EVENT is worth the wait a
  /// REQ is spared.
  Future<({RelayConnection? relay, RelayFailure? failure})> _open(
    BroadcastState state,
    RelayConnectionKey key, {
    NostrSigner? as,
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    final opening = await _connections.ensureOpen(
      key,
      as: as,
      pausing: state,
      connectTimeout: connectTimeout,
      retryUnreachable: true,
    );
    switch (opening) {
      case Opened(:final connection):
        return (relay: connection, failure: null);
      case NotOpened(:final failure):
        return (relay: null, failure: failure);
      case ComingBack():
        final back = await Future.any([
          _connections.whenBack(key),
          state.publishDoneFuture.then((_) => false, onError: (_, _) => false),
        ]);
        final connection = _connections.relays[key];
        if (back && connection != null && connection.isConnected) {
          return (relay: connection, failure: null);
        }
        return (
          relay: null,
          failure: const RelayFailure(
            RelayFailureKind.unreachable,
            "did not come back",
          ),
        );
    }
  }

  /// A relay answers every EVENT it receives, and the same event can be in
  /// flight in several broadcasts. An acceptance means the relay holds the
  /// event, so it answers all of them; a refusal answers a single EVENT.
  void routeOk(
    String eventId,
    RelayConnection connection,
    bool success,
    String msg,
  ) {
    final waiting = _broadcastsWaitingOn(eventId, connection.url);
    if (waiting.isEmpty) {
      logger.warning(
        () =>
            "Received OK for broadcast $eventId from ${connection.url} but no broadcast is waiting for it",
      );
      return;
    }

    // not an answer yet: each broadcast retries under its own auth policy,
    // unless the relay refused the identity this connection already proved
    if (!success &&
        msg.startsWith("auth-required") &&
        !_auth.isAuthenticated(connection.key)) {
      for (final broadcastState in waiting) {
        _handleBroadcastAuthRequired(broadcastState, connection, msg);
      }
      return;
    }

    for (final broadcastState in success ? waiting : waiting.take(1)) {
      broadcastState.networkController.add((
        url: connection.url,
        outcome: RelayPublishOutcome(
          okReceived: true,
          accepted: success,
          message: msg,
        ),
      ));
    }
  }

  /// In-flight broadcasts of [eventId] sent to [relayUrl] that have no answer
  /// from it yet.
  List<BroadcastState> _broadcastsWaitingOn(String eventId, RelayUrl relayUrl) {
    final states = inFlight[eventId] ?? const [];
    return states.where((state) {
      final outcome = state.broadcasts[relayUrl];
      return !state.networkController.isClosed &&
          outcome != null &&
          !outcome.okReceived &&
          outcome.failure == null;
    }).toList();
  }

  /// Handles OK auth-required for a broadcast by moving the retry onto an
  /// account-bound connection, authenticating it once, and re-sending EVENT.
  /// Concurrent broadcasts share [RelayConnections.authenticate], avoiding
  /// duplicate AUTH events whose identical ids used to overwrite each other's
  /// callbacks.
  void _handleBroadcastAuthRequired(
    BroadcastState broadcastState,
    RelayConnection connection,
    String refusal,
  ) {
    final relayUrl = connection.url;
    // the refusal of another broadcast of the same event reaches this one too
    if (broadcastState.retryingAuth.contains(relayUrl)) {
      return;
    }

    final eventToResend = broadcastState.event;
    if (eventToResend == null) {
      logger.warning(
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
      logger.warning(
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

    final boundKey = RelayConnectionKey.authenticated(
      relayUrl,
      account.publicKey,
    );

    Future<void> retryOnBoundConnection() async {
      try {
        final (relay: bound, :failure) = await _open(
          broadcastState,
          boundKey,
          as: account,
        );
        if (broadcastState.networkController.isClosed) {
          return;
        }
        if (bound == null) {
          _failBroadcast(
            broadcastState,
            relayUrl,
            failure ?? const RelayFailure(RelayFailureKind.noBoundConnection),
          );
          return;
        }

        // Some relays challenge immediately; others only after seeing EVENT on
        // the bound socket. Trigger the latter, then the next auth-required OK
        // enters this method with the bound key and authenticates below.
        if (connection.key != boundKey && !_auth.isAuthenticated(boundKey)) {
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
        logger.severe(
          () => "Broadcast auth retry failed for $eventId",
          error,
          stackTrace,
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
            state.broadcasts.containsKey(key.url),
      );
}
