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
import 'publish_state.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';
import 'relay_limits.dart';

/// The EVENTs in flight on a `RelayManager`: sending them, routing each OK to
/// the publishes waiting on it and moving them to a bound connection when a
/// relay asks for authentication. Internal to dostr_core.
class PublishesInFlight {
  final RelayConnections _connections;
  final RelayAuth _auth;

  /// key: event id
  /// value: one state per publish, the same event can be in flight several
  /// times at once
  final Map<String, List<PublishState>> inFlight = {};

  PublishesInFlight({
    required RelayConnections connections,
    required RelayAuth auth,
  }) : _connections = connections,
       _auth = auth;

  /// Whether a publish of [eventId] is still waiting on its relays.
  bool isPublishing(String eventId) => inFlight.containsKey(eventId);

  /// Whether the `RelayManager` was disposed.
  bool get disposed => _connections.disposed;

  /// Ends every publish in flight, failing with [failure] the relays that still
  /// owe an answer.
  void endAll(RelayFailure failure) {
    final states = {for (final states in inFlight.values) ...states};
    for (final state in states) {
      for (final url in state.outcomes.keys.toList()) {
        if (state.owesAnswer(url)) _failRelay(state, url, failure);
      }
      state.closeIfNoRelays();
    }
  }

  /// Tracks [relayUrl] in [state], so its OK can be routed back.
  void _registerRelay(PublishState state, RelayUrl relayUrl, Nip01Event event) {
    state.event ??= event;

    if (state.outcomes[relayUrl] == null) {
      state.outcomes[relayUrl] = const RelayPublishOutcome();
    } else {
      logger.warning(
        () =>
            "_registerRelay: $relayUrl already registered for ${event.id}, skipping",
      );
    }
  }

  void _failRelay(PublishState state, RelayUrl relay, RelayFailure failure) {
    if (state.isOver) {
      logger.warning(
        () =>
            "Ignoring a late failure of ${state.event?.id} on $relay: the publish is over",
      );
      return;
    }
    state.report(relay, RelayPublishOutcome(failure: failure));
  }

  /// Tracks [state] as a publish of [eventId] until it is done, so the OK of
  /// the relays reach it.
  void track(String eventId, PublishState state) {
    inFlight.putIfAbsent(eventId, () => []).add(state);
    void untrack() {
      final states = inFlight[eventId];
      if (states == null) return;
      states.remove(state);
      if (states.isEmpty) inFlight.remove(eventId);
    }

    state.done.then((_) => untrack(), onError: (_, _) => untrack());
  }

  /// Sends [event] to [url] for [state], on the connection its [AuthPolicy]
  /// allows. The relay is tracked before this returns, and reported as failed
  /// when the EVENT cannot go out.
  Future<void> publishToRelay(
    PublishState state,
    RelayUrl url,
    Nip01Event event, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    _registerRelay(state, url, event);
    try {
      final (:relay, :failure) = await _connectionFor(
        state,
        url,
        connectTimeout: connectTimeout,
      );
      if (relay == null) {
        _failRelay(
          state,
          url,
          failure ?? const RelayFailure(RelayFailureKind.unreachable),
        );
        return;
      }
      await _connections.sendOrThrow(
        relay,
        ClientMsg(ClientMsgType.kEvent, event: event).toJson(),
      );
      state.writtenOn[url] = relay.key;
    } on MessageTooLong catch (error) {
      _failRelay(state, url, error.failure);
    } catch (error) {
      _failRelay(
        state,
        url,
        RelayFailure(RelayFailureKind.connectionLost, "$error"),
      );
    }
  }

  /// Sends again on [connection] the EVENTs the socket it replaces took
  /// without the relay answering them.
  void replayOn(RelayConnection connection) {
    for (final state in _owedOn(connection.key)) {
      unawaited(_resend(state, connection));
    }
  }

  /// Fails the relays that took an EVENT on [key] without answering it, once
  /// nothing will bring that connection back.
  void endPublishesOn(RelayConnectionKey key) {
    for (final state in _owedOn(key)) {
      _failRelay(
        state,
        key.url,
        const RelayFailure(
          RelayFailureKind.connectionLost,
          "the connection went away before the relay answered",
        ),
      );
    }
  }

  /// The publishes whose EVENT was written on [key] and is still unanswered
  /// there, each once although it may be tracked under two ids.
  Set<PublishState> _owedOn(RelayConnectionKey key) => {
    for (final states in inFlight.values)
      for (final state in states)
        if (state.writtenOn[key.url] == key &&
            state.owesAnswer(key.url) &&
            !state.retryingAuth.contains(key.url))
          state,
  };

  Future<void> _resend(PublishState state, RelayConnection connection) async {
    final event = state.event!;
    try {
      await _connections.sendOrThrow(
        connection,
        ClientMsg(ClientMsgType.kEvent, event: event).toJson(),
      );
    } on MessageTooLong catch (error) {
      _failRelay(state, connection.url, error.failure);
    } catch (error) {
      // gone again: its next comeback sends it, or endPublishesOn fails it
      logger.fine(
        () => "EVENT ${event.id} not sent again to ${connection.url}: $error",
      );
    }
  }

  /// The connection [state] must go out on towards [url], opening it when it
  /// is not there yet, or why nothing may be sent.
  ///
  /// Owns the connecting too: a publish that requires an identity must not
  /// even open the anonymous connection, because a socket we opened is one the
  /// relay saw, whether or not anything was sent on it.
  Future<({RelayConnection? relay, RelayFailure? failure})> _connectionFor(
    PublishState state,
    RelayUrl url, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) async {
    final auth = state.auth;
    final key = RelayConnectionKey.forAuth(url, auth);
    if (key == null) {
      logger.warning(
        () => "Publish requires ${auth?.signer?.publicKey}, which cannot sign",
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
    PublishState state,
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
          state.done.then((_) => false, onError: (_, _) => false),
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
  /// flight in several publishes. An acceptance means the relay holds the
  /// event, so it answers all of them; a refusal answers a single EVENT.
  void routeOk(
    String eventId,
    RelayConnection connection,
    bool success,
    String msg,
  ) {
    final waiting = _waitingOn(eventId, connection.url);
    if (waiting.isEmpty) {
      logger.warning(
        () =>
            "Received OK for $eventId from ${connection.url} but no publish is waiting for it",
      );
      return;
    }

    // not an answer yet: each publish retries under its own auth policy,
    // unless the relay refused the identity this connection already proved
    if (!success &&
        msg.startsWith("auth-required") &&
        !connection.isAuthenticated) {
      for (final state in waiting) {
        _handleAuthRequired(state, connection, msg);
      }
      return;
    }

    for (final state in success ? waiting : waiting.take(1)) {
      state.report(
        connection.url,
        RelayPublishOutcome(okReceived: true, accepted: success, message: msg),
      );
    }
  }

  /// In-flight publishes of [eventId] sent to [relayUrl] that have no answer
  /// from it yet.
  List<PublishState> _waitingOn(String eventId, RelayUrl relayUrl) {
    final states = inFlight[eventId] ?? const [];
    return states.where((state) => state.owesAnswer(relayUrl)).toList();
  }

  /// Handles OK auth-required for a publish by moving the retry onto an
  /// account-bound connection, authenticating it once, and re-sending EVENT.
  /// Concurrent publishes share [RelayConnections.authenticate], avoiding
  /// duplicate AUTH events whose identical ids used to overwrite each other's
  /// callbacks.
  void _handleAuthRequired(
    PublishState state,
    RelayConnection connection,
    String refusal,
  ) {
    final relayUrl = connection.url;
    // the refusal of another publish of the same event reaches this one too
    if (state.retryingAuth.contains(relayUrl)) {
      return;
    }

    final eventToResend = state.event;
    if (eventToResend == null) {
      logger.warning(
        () =>
            "Received OK auth-required from $relayUrl but no event stored for the publish",
      );
      return;
    }
    final eventId = eventToResend.id;

    final account = _auth.accountForPublish(state.auth, eventToResend);
    if (account == null) {
      logger.warning(
        () => "Cannot satisfy auth-required for publish $eventId on $relayUrl",
      );
      _failRelay(
        state,
        relayUrl,
        RelayFailure(RelayFailureKind.identityNotAllowed, refusal),
      );
      return;
    }

    final boundKey = RelayConnectionKey.authenticated(
      relayUrl,
      account.publicKey,
    );

    Future<void> retryOnBoundConnection() async {
      try {
        final (relay: bound, :failure) = await _open(
          state,
          boundKey,
          as: account,
        );
        if (state.isOver) {
          return;
        }
        if (bound == null) {
          _failRelay(
            state,
            relayUrl,
            failure ?? const RelayFailure(RelayFailureKind.noBoundConnection),
          );
          return;
        }

        // Some relays challenge immediately; others only after seeing EVENT on
        // the bound socket. Trigger the latter, then the next auth-required OK
        // enters this method with the bound key and authenticates below.
        if (connection.key != boundKey && !bound.isAuthenticated) {
          await _connections.sendOrThrow(
            bound,
            ClientMsg(ClientMsgType.kEvent, event: eventToResend).toJson(),
          );
          state.writtenOn[relayUrl] = boundKey;
          return;
        }

        final accepted = await _connections.authenticate(boundKey);
        if (state.isOver) {
          return;
        }
        if (!accepted) {
          _failRelay(
            state,
            relayUrl,
            const RelayFailure(RelayFailureKind.authenticationFailed),
          );
          return;
        }
        await _connections.sendOrThrow(
          bound,
          ClientMsg(ClientMsgType.kEvent, event: eventToResend).toJson(),
        );
        state.writtenOn[relayUrl] = boundKey;
      } catch (error, stackTrace) {
        logger.severe(
          () => "Publish auth retry failed for $eventId",
          error,
          stackTrace,
        );
        if (!state.isOver) {
          _failRelay(
            state,
            relayUrl,
            error is MessageTooLong
                ? error.failure
                : RelayFailure(RelayFailureKind.connectionLost, "$error"),
          );
        }
      } finally {
        state.retryingAuth.remove(relayUrl);
      }
    }

    state.retryingAuth.add(relayUrl);
    unawaited(retryOnBoundConnection());
  }

  /// Whether a publish still waits on the relay behind [key]. Publishes track
  /// relay urls rather than identities, so every connection to that relay
  /// counts.
  bool hasWorkOn(RelayConnectionKey key) => inFlight.values
      .expand((states) => states)
      .any((state) => !state.isOver && state.outcomes.containsKey(key.url));
}
