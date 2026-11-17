import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../shared/logger.dart';
import '../../../shared/nips/nip01/client_messages.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_failure.dart';
import '../../entities/relay_publish_outcome.dart';
import 'publish_state.dart';
import 'relay_auth.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';
import 'relay_limits.dart';

/// A publish waiting on one of its relays.
typedef _Waiting = ({PublishState state, RelayPublishState relay});

/// Why a publish cannot go out on a connection.
class _NotOpened implements Exception {
  final RelayFailure failure;

  const _NotOpened(this.failure);

  @override
  String toString() => "$failure";
}

/// The EVENTs in flight on a `RelayManager`: sending them, routing each OK to
/// the publishes waiting on it and moving them to a bound connection when a
/// relay asks for authentication. Internal to dostr_core.
class PublishesInFlight {
  final RelayConnections _connections;
  final RelayAuth _auth;

  /// the publishes of each event id: the same event can be in flight several
  /// times at once
  final Map<String, List<PublishState>> inFlight = {};

  PublishesInFlight({
    required RelayConnections connections,
    required RelayAuth auth,
  }) : _connections = connections,
       _auth = auth;

  /// Whether the `RelayManager` was disposed.
  bool get disposed => _connections.disposed;

  /// Ends every publish in flight, failing with [failure] the relays that still
  /// owe an answer.
  void endAll(RelayFailure failure) {
    for (final state in {for (final states in inFlight.values) ...states}) {
      for (final url in state.relays.keys) {
        state.end(url, RelayPublishOutcome.failed(failure));
      }
    }
  }

  void _fail(
    PublishState state,
    RelayPublishState relay,
    RelayFailure failure,
  ) => state.end(relay.url, RelayPublishOutcome.failed(failure));

  static RelayFailure _failureOf(Object error) => switch (error) {
    MessageTooLong(:final failure) || _NotOpened(:final failure) => failure,
    _ => RelayFailure(RelayFailureKind.connectionLost, "$error"),
  };

  /// Sends the event of [state] to each of its relays, and tracks [state]
  /// until it is over, so the OK of the relays reach it.
  void start(PublishState state) {
    final eventId = state.event.id;
    inFlight.putIfAbsent(eventId, () => []).add(state);
    state.done.then((_) {
      final states = inFlight[eventId];
      if (states == null) return;
      states.remove(state);
      if (states.isEmpty) inFlight.remove(eventId);
    });
    for (final relay in state.relays.values) {
      unawaited(_publishTo(state, relay));
    }
  }

  /// Sends the event of [state] to [relay], on the connection its
  /// [AuthPolicy] allows, and fails the relay when the EVENT cannot go out.
  ///
  /// A publish that requires an identity must not even open the anonymous
  /// connection: a socket we opened is one the relay saw, whether or not
  /// anything was sent on it.
  Future<void> _publishTo(PublishState state, RelayPublishState relay) async {
    final key = relay.key;
    if (key == null) {
      logger.warning(
        () =>
            "Publish requires ${state.auth?.signer?.publicKey}, which cannot sign",
      );
      _fail(state, relay, const RelayFailure(RelayFailureKind.cannotSign));
      return;
    }
    try {
      final connection = await _open(state, key, as: state.auth?.signer);
      await _write(state, relay, connection);
    } catch (error) {
      _fail(state, relay, _failureOf(error));
    }
  }

  /// Writes the event of [state] on [connection], where [relay] then waits for
  /// its OK, unless it moved to a bound connection meanwhile. Throws when the
  /// socket went away first.
  Future<void> _write(
    PublishState state,
    RelayPublishState relay,
    RelayConnection connection,
  ) async {
    await _connections.sendOrThrow(connection, eventMessage(state.event));
    if (relay.key == connection.key) {
      relay.progress = RelayPublishProgress.written;
    }
  }

  /// The connection behind [key] once it is open. One that is coming back is
  /// waited for while [state] lasts. Throws a [_NotOpened] that says why
  /// [state] cannot go out on it.
  ///
  /// A relay tried a moment ago is tried again: an EVENT is worth the wait a
  /// REQ is spared.
  Future<RelayConnection> _open(
    PublishState state,
    RelayConnectionKey key, {
    NostrSigner? as,
  }) async {
    final opening = await _connections.ensureOpen(
      key,
      as: as,
      pausing: state,
      retryUnreachable: true,
    );
    switch (opening) {
      case Opened(:final connection):
        return connection;
      case NotOpened(:final failure):
        throw _NotOpened(failure);
      case ComingBack():
        final back = await Future.any([
          _connections.whenBack(key),
          state.done.then((_) => false),
        ]);
        final connection = _connections.relays[key];
        if (back && connection != null && connection.isConnected) {
          return connection;
        }
        throw const _NotOpened(
          RelayFailure(RelayFailureKind.unreachable, "did not come back"),
        );
    }
  }

  /// Sends again on [connection] the EVENTs the socket it replaces took
  /// without the relay answering them.
  void replayOn(RelayConnection connection) {
    for (final (:state, :relay) in _owedOn(connection.key)) {
      unawaited(_resend(state, relay, connection));
    }
  }

  /// Fails the relays that took an EVENT on [key] without answering it, once
  /// nothing will bring that connection back.
  void endPublishesOn(RelayConnectionKey key) {
    for (final (:state, :relay) in _owedOn(key)) {
      _fail(
        state,
        relay,
        const RelayFailure(
          RelayFailureKind.connectionLost,
          "the connection went away before the relay answered",
        ),
      );
    }
  }

  /// The publishes whose EVENT was written on [key] and is still unanswered
  /// there.
  List<_Waiting> _owedOn(RelayConnectionKey key) => [
    for (final states in inFlight.values)
      for (final state in states)
        if (state.relays[key.url] case final relay? when relay.isOwedOn(key))
          if (!state.isOver) (state: state, relay: relay),
  ];

  Future<void> _resend(
    PublishState state,
    RelayPublishState relay,
    RelayConnection connection,
  ) async {
    try {
      await _write(state, relay, connection);
    } on MessageTooLong catch (error) {
      _fail(state, relay, error.failure);
    } catch (error) {
      // gone again: its next comeback sends it, or endPublishesOn fails it
      logger.fine(
        () =>
            "EVENT ${state.event.id} not sent again to ${connection.url}: $error",
      );
    }
  }

  /// A relay answers every EVENT it receives, and the same event can be in
  /// flight in several publishes. An acceptance means the relay holds the
  /// event, so it answers all of them; a refusal answers a single EVENT, the
  /// one written on [connection] when there is one.
  void routeOk(
    String eventId,
    RelayConnection connection,
    bool success,
    String message,
  ) {
    final waiting = _waitingOn(eventId, connection.url);
    if (waiting.isEmpty) {
      logger.fine(
        () =>
            "OK for $eventId from ${connection.url}, which no publish waits for",
      );
      return;
    }

    // not an answer yet: each publish on this connection retries under its own
    // auth policy, unless the relay refused the identity this connection
    // already proved. One on another connection waits for its own OK.
    if (!success &&
        message.startsWith("auth-required") &&
        !connection.isAuthenticated) {
      for (final (:state, :relay) in waiting) {
        if (!relay.isPendingOn(connection.key)) continue;
        _handleAuthRequired(state, relay, connection, message);
      }
      return;
    }

    if (success) {
      for (final (:state, :relay) in waiting) {
        state.end(relay.url, RelayPublishOutcome.accepted(message));
      }
      return;
    }
    final (:state, :relay) = waiting.firstWhere(
      (waiting) => waiting.relay.isOwedOn(connection.key),
      orElse: () => waiting.first,
    );
    state.end(relay.url, RelayPublishOutcome.refused(message));
  }

  /// The publishes of [eventId] that have yet to hear from [url].
  List<_Waiting> _waitingOn(String eventId, RelayUrl url) => [
    for (final state in inFlight[eventId] ?? const <PublishState>[])
      if (state.relays[url] case final relay? when relay.isPending)
        if (!state.isOver) (state: state, relay: relay),
  ];

  /// Moves [relay] to the connection bound to the identity the [AuthPolicy]
  /// of [state] allows, after [connection] refused it with [refusal].
  void _handleAuthRequired(
    PublishState state,
    RelayPublishState relay,
    RelayConnection connection,
    String refusal,
  ) {
    // the refusal of another publish of the same event reaches this one too
    if (relay.progress == RelayPublishProgress.retryingAuth) return;

    final account = _auth.accountForPublish(state.auth, state.event);
    if (account == null) {
      logger.fine(
        () =>
            "Cannot satisfy auth-required for publish ${state.event.id} on ${relay.url}",
      );
      _fail(
        state,
        relay,
        RelayFailure(RelayFailureKind.identityNotAllowed, refusal),
      );
      return;
    }
    relay
      ..key = RelayConnectionKey.authenticated(relay.url, account.publicKey)
      ..progress = RelayPublishProgress.retryingAuth;
    unawaited(_retryOnBound(state, relay, account, refusedOn: connection.key));
  }

  /// Sends the event of [state] again on the bound connection of [relay],
  /// authenticated as [account] unless the refusal came from another
  /// connection.
  ///
  /// Some relays challenge right away, others only once they see an EVENT on
  /// the bound socket: that EVENT is the trigger, and the auth-required it may
  /// get comes back to [_handleAuthRequired] from the bound connection.
  /// Concurrent publishes share [RelayConnections.authenticate], so they send
  /// a single AUTH.
  Future<void> _retryOnBound(
    PublishState state,
    RelayPublishState relay,
    NostrSigner account, {
    required RelayConnectionKey refusedOn,
  }) async {
    final bound = relay.key!;
    try {
      final connection = await _open(state, bound, as: account);
      if (state.isOver) return;
      if (refusedOn != bound && !connection.isAuthenticated) {
        await _write(state, relay, connection);
        return;
      }
      final accepted = await _connections.authenticate(bound);
      if (state.isOver) return;
      if (!accepted) {
        _fail(
          state,
          relay,
          const RelayFailure(RelayFailureKind.authenticationFailed),
        );
        return;
      }
      await _write(state, relay, connection);
    } on _NotOpened catch (error) {
      _fail(state, relay, error.failure);
    } catch (error, stackTrace) {
      logger.warning(
        () => "Could not publish ${state.event.id} on $bound",
        error,
        stackTrace,
      );
      _fail(state, relay, _failureOf(error));
    }
  }

  /// Whether a publish still waits on the connection behind [key]: for it to
  /// open or come back, for an OK, or for an authentication.
  bool hasWorkOn(RelayConnectionKey key) => inFlight.values.any(
    (states) => states.any(
      (state) =>
          !state.isOver && (state.relays[key.url]?.isPendingOn(key) ?? false),
    ),
  );
}
