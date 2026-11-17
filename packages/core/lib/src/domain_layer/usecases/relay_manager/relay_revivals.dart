import 'dart:async';

import '../../../config/relay_defaults.dart';
import '../../../shared/logger.dart';
import '../../entities/relay_failure.dart';
import 'backoff.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';

/// The revival of a [RelayConnection] whose socket dropped: while it is
/// brought back, then while the socket it brought back is young.
class Revival {
  final BinaryExponentialBackoff backoff;
  final Stopwatch since = Stopwatch()..start();

  /// how long the socket it brought back has lived
  final Stopwatch up = Stopwatch();

  /// the retirement of the socket that dropped, which the next attempt waits
  /// for
  Future<void> retired;

  Timer? next;
  Future<RelayFailure?>? attempt;

  /// whether it brought its connection back
  bool back = false;

  /// completes once the connection is back, given up or no longer revived
  Completer<void> settled = Completer();

  Revival(Duration maximumDelay, this.retired)
    : backoff = BinaryExponentialBackoff(
        initial: reconnectInitialDelay,
        maximum: maximumDelay,
      );

  void _settle() {
    if (!settled.isCompleted) settled.complete();
  }
}

/// Brings back the connections of [RelayConnections] whose socket dropped: one
/// attempt right away, then one after each wait of a backoff, until one is back
/// or [reconnectGiveUpAfter] gave up on it. Internal to dostr_core.
class RelayRevivals {
  final RelayConnections _connections;
  final Duration _maximumDelay;

  RelayRevivals(this._connections, {required Duration maximumDelay})
    : _maximumDelay = maximumDelay;

  /// Whether [connection] dropped and is being brought back.
  bool isReviving(RelayConnection connection) =>
      connection.revival?.back == false;

  /// Completes once [connection] is back, given up or no longer revived, null
  /// when it is not being brought back.
  Future<void>? settled(RelayConnection connection) =>
      isReviving(connection) ? connection.revival!.settled.future : null;

  /// Brings [connection] back once [retired], the socket that dropped: right
  /// away, or after the next step of the backoff when the socket the last
  /// revival brought back dropped before [reconnectStableAfter], so a relay
  /// that drops every socket it gets is not reconnected in a loop.
  void comeBack(RelayConnection connection, Future<void> retired) {
    final previous = connection.revival;
    if (previous != null &&
        previous.back &&
        previous.up.elapsed < reconnectStableAfter) {
      previous
        ..back = false
        ..retired = retired
        ..settled = Completer()
        ..next = Timer(previous.backoff.next(), () => hurry(connection));
      return;
    }
    stop(connection);
    connection.revival = Revival(_maximumDelay, retired);
    unawaited(hurry(connection));
  }

  /// Attempts to bring [connection] back now, without waiting for the next
  /// step of its backoff, and says why it is not back.
  Future<RelayFailure?> hurry(RelayConnection connection) {
    final revival = connection.revival;
    if (revival == null || revival.back) {
      return Future.value(const RelayFailure(RelayFailureKind.connectionLost));
    }
    revival.next?.cancel();
    return revival.attempt ??= _attempt(
      connection,
      revival,
    ).whenComplete(() => revival.attempt = null);
  }

  Future<RelayFailure?> _attempt(
    RelayConnection connection,
    Revival revival,
  ) async {
    await revival.retired;
    final connections = _connections;
    final key = connection.key;
    if (!identical(connection.revival, revival)) {
      return const RelayFailure(RelayFailureKind.connectionLost);
    }
    // an open one was just opened by a caller that has yet to use it
    if (!connection.isConnected && !connections.hasWorkOn(key)) {
      logger.info(() => "nothing left to reconnect $key for");
      await connections.closeConnection(key);
      return const RelayFailure(RelayFailureKind.connectionLost);
    }
    final failure = await connections.reopen(connection);
    // closed or reset meanwhile, which settled what it carried
    if (!identical(connection.revival, revival)) return failure;
    if (failure == null) {
      revival
        ..back = true
        .._settle();
      revival.since.reset();
      revival.up
        ..reset()
        ..start();
      connections.listener.replayOn(connection);
      connections.listener.endAuthRetriesOn(key);
      return null;
    }
    if (!connections.allowReconnect ||
        revival.since.elapsed >= reconnectGiveUpAfter) {
      stop(connection);
      connections.listener.endAuthRetriesOn(key);
      connections.listener.giveUpOn(key);
      return failure;
    }
    revival.next = Timer(revival.backoff.next(), () => hurry(connection));
    return failure;
  }

  /// Stops bringing [connection] back, and forgets that it was.
  void stop(RelayConnection connection) {
    final revival = connection.revival;
    connection.revival = null;
    revival?.next?.cancel();
    revival?._settle();
  }
}
