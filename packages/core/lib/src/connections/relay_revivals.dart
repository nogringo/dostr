import 'dart:async';

import '../config/relay_defaults.dart';
import '../helpers/logger.dart';
import '../relay_failure.dart';
import 'backoff.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';

/// The bringing back of a [RelayConnection] whose socket dropped.
///
/// It lasts while the connection is being brought back, then while the socket
/// it brought back is young: a socket that drops young is retried after the
/// next step of the same backoff.
class Revival {
  Revival(Duration maximumDelay, this._retired)
    : _backoff = BinaryExponentialBackoff(
        initial: reconnectInitialDelay,
        maximum: maximumDelay,
      );

  final BinaryExponentialBackoff _backoff;
  // since the drop, or since the connection was last back
  final Stopwatch _trying = Stopwatch()..start();
  final Stopwatch _up = Stopwatch();
  Future<void> _retired;
  Timer? _next;
  Future<RelayFailure?>? _attempt;
  bool _back = false;
  Completer<void> _settled = Completer();

  /// Whether the connection is still being brought back.
  bool get isReviving => !_back;

  /// Completes once the connection is back, given up, or no longer revived.
  Future<void> get settled => _settled.future;

  /// Completes once the socket that dropped is closed. An attempt waits for it.
  Future<void> get retired => _retired;

  /// How long it has been trying since the drop.
  Duration get tryingFor => _trying.elapsed;

  /// Whether the socket it brought back dropped before [reconnectStableAfter].
  bool get droppedYoung => _back && _up.elapsed < reconnectStableAfter;

  /// Runs [attempt], unless one is under way, and returns the attempt under
  /// way. The wait for the next step of the backoff is cancelled.
  Future<RelayFailure?> attempt(Future<RelayFailure?> Function() attempt) {
    _next?.cancel();
    return _attempt ??= attempt().whenComplete(() => _attempt = null);
  }

  /// Runs [retry] after the next step of the backoff.
  void retryLater(void Function() retry) =>
      _next = Timer(_backoff.next(), retry);

  /// The connection is back, on a socket that starts aging now.
  void cameBack() {
    _back = true;
    _settle();
    _trying.reset();
    _up
      ..reset()
      ..start();
  }

  /// The socket it brought back dropped young. The connection is brought back
  /// again once [retired], after the next step of the backoff.
  void droppedAgain(Future<void> retired, void Function() retry) {
    _back = false;
    _retired = retired;
    _settled = Completer();
    retryLater(retry);
  }

  /// No more attempts, and whatever waits for it settles.
  void stop() {
    _next?.cancel();
    _settle();
  }

  void _settle() {
    if (!_settled.isCompleted) _settled.complete();
  }
}

/// Brings back the connections of [RelayConnections] whose socket dropped.
/// Internal to dostr_core.
///
/// The first attempt is immediate. Each later one waits for the next step of a
/// backoff. It goes on until the connection is back, or until `giveUpAfter`
/// passed, when it is not null.
class RelayRevivals {
  final RelayConnections _connections;
  final Duration _maximumDelay;
  final Duration? _giveUpAfter;

  RelayRevivals(
    this._connections, {
    required Duration maximumDelay,
    Duration? giveUpAfter,
  }) : _maximumDelay = maximumDelay,
       _giveUpAfter = giveUpAfter;

  /// Whether [connection] dropped and is being brought back.
  bool isReviving(RelayConnection connection) =>
      connection.revival?.isReviving ?? false;

  /// Completes once [connection] is back, given up, or no longer revived. Null
  /// when it is not being brought back.
  Future<void>? settled(RelayConnection connection) =>
      isReviving(connection) ? connection.revival!.settled : null;

  /// Brings [connection] back once [retired], the socket that dropped, is
  /// closed.
  ///
  /// The first attempt is immediate, unless the socket the last revival
  /// brought back dropped young. It then waits for the next step of that
  /// revival's backoff, so a relay that drops every socket is not reconnected
  /// in a loop.
  void comeBack(RelayConnection connection, Future<void> retired) {
    final previous = connection.revival;
    if (previous != null && previous.droppedYoung) {
      previous.droppedAgain(retired, () => hurry(connection));
      return;
    }
    stop(connection);
    connection.revival = Revival(_maximumDelay, retired);
    unawaited(hurry(connection));
  }

  /// Tries to bring [connection] back now, without waiting for the next step
  /// of its backoff, and says why it is not back.
  Future<RelayFailure?> hurry(RelayConnection connection) {
    final revival = connection.revival;
    if (revival == null || !revival.isReviving) {
      return Future.value(const RelayFailure(RelayFailureKind.connectionLost));
    }
    return revival.attempt(() => _attempt(connection, revival));
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
      revival.cameBack();
      connections.listener.onBack(connection);
      return null;
    }
    if (!connections.allowReconnect || _gaveUp(revival)) {
      stop(connection);
      connections.listener.onGone(key);
      return failure;
    }
    revival.retryLater(() => hurry(connection));
    return failure;
  }

  bool _gaveUp(Revival revival) {
    final giveUpAfter = _giveUpAfter;
    return giveUpAfter != null && revival.tryingFor >= giveUpAfter;
  }

  /// Stops bringing [connection] back, and forgets that it was.
  void stop(RelayConnection connection) {
    final revival = connection.revival;
    connection.revival = null;
    revival?.stop();
  }
}
