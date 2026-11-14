import 'dart:async';

import '../../../shared/logger/logger.dart';
import 'relay_connection.dart';
import 'relay_connections.dart';

/// Closes the connections of [RelayConnections] that went without work for
/// their idle timeout. Internal to dostr_core.
class IdleConnections {
  final RelayConnections _connections;
  final Duration? _anonymousTimeout;
  final Duration? _authenticatedTimeout;
  Timer? _sweep;
  bool _sweeping = false;

  IdleConnections(
    this._connections, {
    Duration? anonymousTimeout,
    Duration? authenticatedTimeout,
  }) : _anonymousTimeout = anonymousTimeout,
       _authenticatedTimeout = authenticatedTimeout;

  /// Starts closing the connections left idle, unless no idle timeout is set.
  /// It checks every quarter of the shortest one, and stops once no
  /// connection is left.
  void watch() {
    if (_sweep != null) return;
    final timeouts = [?_anonymousTimeout, ?_authenticatedTimeout];
    if (timeouts.isEmpty) return;
    final shortest = timeouts.reduce((a, b) => a < b ? a : b);
    final period = shortest ~/ 4;
    const finest = Duration(milliseconds: 1);
    _sweep = Timer.periodic(period < finest ? finest : period, (_) {
      unawaited(
        _closeIdle().catchError((Object error) {
          Logger.log.e(() => "Could not close idle connections", error: error);
        }),
      );
    });
  }

  void stop() {
    _sweep?.cancel();
    _sweep = null;
  }

  /// Work is polled, since a protocol handler only tells when asked: the
  /// traffic counted by [RelayConnection.idleFor] catches the work that
  /// started and ended between two checks.
  Future<void> _closeIdle() async {
    if (_sweeping) return;
    _sweeping = true;
    final connections = _connections;
    var changed = false;
    try {
      for (final key in connections.relays.keys.toList()) {
        final connectivity = connections.relays[key];
        final timeout = key.isAnonymous
            ? _anonymousTimeout
            : _authenticatedTimeout;
        if (connectivity == null || timeout == null) continue;
        if (connections.hasWorkOn(key)) {
          connectivity.idleFor.reset();
          continue;
        }
        if (connectivity.idleFor.elapsed < timeout) continue;
        Logger.log.d(
          () => "closing $key, idle for ${connectivity.idleFor.elapsed}",
        );
        await connections.closeConnection(key);
        changed = true;
      }
    } finally {
      _sweeping = false;
      if (changed) connections.notifyChanged();
      if (connections.relays.isEmpty) stop();
    }
  }
}
