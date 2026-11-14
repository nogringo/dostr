import 'dart:async';

import '../../../config/relay_defaults.dart';
import '../../../shared/logger/logger.dart';
import '../../entities/relay_connection_key.dart';
import 'backoff.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';

/// A connection whose socket dropped, while it is being brought back.
class _Revival {
  final RelayConnection connectivity;
  final BinaryExponentialBackoff backoff;
  final Stopwatch since = Stopwatch()..start();

  /// how long the socket it brought back has lived
  final Stopwatch up = Stopwatch();
  Timer? next;
  Future<bool>? attempt;

  _Revival(this.connectivity, int maximumStep)
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

  /// Whether the connection behind [key] is being brought back and waits for
  /// its next attempt.
  bool isWaiting(RelayConnectionKey key) {
    final revival = _revivals[key];
    return revival != null && revival.attempt == null;
  }

  /// Brings [connectivity] back after its socket dropped: one attempt now, then
  /// one after each wait of its backoff, until it is back or given up.
  Future<bool> revive(RelayConnection connectivity) {
    final key = connectivity.key;
    var revival = _revivals[key];
    if (revival == null || !identical(revival.connectivity, connectivity)) {
      revival = _revivals[key] = _Revival(connectivity, _maximumStep);
    }
    revival.next?.cancel();
    final current = revival;
    return revival.attempt ??= _attempt(
      revival,
    ).whenComplete(() => current.attempt = null);
  }

  Future<bool> _attempt(_Revival revival) async {
    final connectivity = revival.connectivity;
    final key = connectivity.key;
    final connections = _connections;
    // an open one was just opened by a caller that has yet to use it
    if (!connections.isConnectionOpen(key) && !connections.hasWorkOn(key)) {
      Logger.log.i(() => "nothing left to reconnect $key for");
      await connections.closeConnection(key);
      connections.notifyChanged();
      return false;
    }
    final connected = await connections
        .reconnectConnection(key, force: true)
        .catchError((Object error) {
          Logger.log.e(() => "Could not reconnect $key", error: error);
          return false;
        });
    // closed or reset meanwhile, which settled what it carried
    if (!identical(_revivals[key], revival)) return connected;
    connections.notifyChanged();
    if (connected) {
      _revivals.remove(key);
      _revived[key] = revival;
      revival.since.reset();
      revival.up
        ..reset()
        ..start();
      connections.listener.replayOn(connectivity);
      connections.listener.endAuthRetriesOn(key);
      return true;
    }
    if (!connections.allowReconnect ||
        revival.since.elapsed >= reconnectGiveUpAfter) {
      _revivals.remove(key);
      connections.listener.endAuthRetriesOn(key);
      connections.listener.endRequestsOn(key);
      return false;
    }
    revival.next = Timer(revival.backoff.next(), () => revive(connectivity));
    return false;
  }

  /// Stops bringing back the connection behind [key], and forgets that it was.
  void stop(RelayConnectionKey key) {
    _revived.remove(key);
    _revivals.remove(key)?.next?.cancel();
  }

  /// Forgets that the connection behind [key] was brought back: its socket
  /// dropped and nothing will bring it back again.
  void forgetRevived(RelayConnectionKey key) => _revived.remove(key);

  /// Takes up again the revival that brought [connectivity] back, when its
  /// socket dropped before [reconnectStableAfter]: the next attempt waits
  /// the next step of its backoff, so a relay that drops every socket it gets
  /// is not reconnected in a loop. Says whether it did.
  bool resume(RelayConnection connectivity) {
    final key = connectivity.key;
    final revival = _revived.remove(key);
    if (revival == null ||
        !identical(revival.connectivity, connectivity) ||
        revival.up.elapsed >= reconnectStableAfter) {
      return false;
    }
    _revivals[key] = revival;
    revival.next = Timer(revival.backoff.next(), () => revive(connectivity));
    return true;
  }
}
