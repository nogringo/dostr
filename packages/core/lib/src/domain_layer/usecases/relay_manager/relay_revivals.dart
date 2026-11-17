import 'dart:async';

import '../../../config/relay_defaults.dart';
import '../../../shared/logger.dart';
import '../../entities/relay_connection_key.dart';
import 'backoff.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';

/// A connection whose socket dropped, while it is being brought back.
class _Revival {
  final RelayConnection connection;
  final BinaryExponentialBackoff backoff;
  final Stopwatch since = Stopwatch()..start();

  /// how long the socket it brought back has lived
  final Stopwatch up = Stopwatch();
  Timer? next;
  Future<bool>? attempt;

  /// completes once the connection is back, given up or no longer revived
  Completer<void> settled = Completer();

  _Revival(this.connection, int maximumStep)
    : backoff = BinaryExponentialBackoff(
        initial: reconnectInitialDelay,
        maximumStep: maximumStep,
      );
}

/// Brings back the connections of [RelayConnections] whose socket dropped: one
/// attempt right away, then one after each wait of a backoff, until one is back
/// or [reconnectGiveUpAfter] gave up on it. Internal to dostr_core.
class RelayRevivals {
  final RelayConnections _connections;
  final int _maximumStep;

  final Map<RelayConnectionKey, _Revival> _revivals = {};

  /// the revivals that brought their connection back, until its socket drops
  final Map<RelayConnectionKey, _Revival> _revived = {};

  RelayRevivals(this._connections, {required int maximumStep})
    : _maximumStep = maximumStep;

  /// Whether the connection behind [key] dropped and is being brought back.
  bool isReviving(RelayConnectionKey key) => _revivals.containsKey(key);

  /// Completes once the connection behind [key] is back, given up or no
  /// longer revived, null when it is not being brought back.
  Future<void>? settled(RelayConnectionKey key) =>
      _revivals[key]?.settled.future;

  static void _settle(_Revival revival) {
    if (!revival.settled.isCompleted) revival.settled.complete();
  }

  /// Whether the connection behind [key] is being brought back and waits for
  /// its next attempt.
  bool isWaiting(RelayConnectionKey key) {
    final revival = _revivals[key];
    return revival != null && revival.attempt == null;
  }

  /// Brings [connection] back after its socket dropped: one attempt now, then
  /// one after each wait of its backoff, until it is back or given up.
  Future<bool> revive(RelayConnection connection) {
    final key = connection.key;
    var revival = _revivals[key];
    if (revival == null || !identical(revival.connection, connection)) {
      if (revival != null) _settle(revival);
      revival = _revivals[key] = _Revival(connection, _maximumStep);
    }
    revival.next?.cancel();
    final current = revival;
    return revival.attempt ??= _attempt(
      revival,
    ).whenComplete(() => current.attempt = null);
  }

  Future<bool> _attempt(_Revival revival) async {
    final connection = revival.connection;
    final key = connection.key;
    final connections = _connections;
    // an open one was just opened by a caller that has yet to use it
    if (!connections.isConnectionOpen(key) && !connections.hasWorkOn(key)) {
      logger.info(() => "nothing left to reconnect $key for");
      await connections.closeConnection(key);
      return false;
    }
    final connected = await connections
        .openNow(key)
        .then((failure) => failure == null)
        .catchError((Object error) {
          logger.severe(() => "Could not reconnect $key", error);
          return false;
        });
    // closed or reset meanwhile, which settled what it carried
    if (!identical(_revivals[key], revival)) return connected;
    if (connected) {
      _revivals.remove(key);
      _settle(revival);
      _revived[key] = revival;
      revival.since.reset();
      revival.up
        ..reset()
        ..start();
      connections.listener.replayOn(connection);
      connections.listener.endAuthRetriesOn(key);
      return true;
    }
    if (!connections.allowReconnect ||
        revival.since.elapsed >= reconnectGiveUpAfter) {
      _revivals.remove(key);
      _settle(revival);
      connections.listener.endAuthRetriesOn(key);
      connections.listener.endRequestsOn(key);
      return false;
    }
    revival.next = Timer(revival.backoff.next(), () => revive(connection));
    return false;
  }

  /// Stops bringing back the connection behind [key], and forgets that it was.
  void stop(RelayConnectionKey key) {
    _revived.remove(key);
    final revival = _revivals.remove(key);
    if (revival == null) return;
    revival.next?.cancel();
    _settle(revival);
  }

  /// Forgets that the connection behind [key] was brought back: its socket
  /// dropped and nothing will bring it back again.
  void forgetRevived(RelayConnectionKey key) => _revived.remove(key);

  /// Takes up again the revival that brought [connection] back, when its
  /// socket dropped before [reconnectStableAfter]: the next attempt waits
  /// the next step of its backoff, so a relay that drops every socket it gets
  /// is not reconnected in a loop. Says whether it did.
  bool resume(RelayConnection connection) {
    final key = connection.key;
    final revival = _revived.remove(key);
    if (revival == null ||
        !identical(revival.connection, connection) ||
        revival.up.elapsed >= reconnectStableAfter) {
      return false;
    }
    _revivals[key] = revival;
    revival.settled = Completer();
    revival.next = Timer(revival.backoff.next(), () => revive(connection));
    return true;
  }
}
