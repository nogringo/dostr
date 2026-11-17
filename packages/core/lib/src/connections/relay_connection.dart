import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../auth/auth_session.dart';
import '../helpers/logger.dart';
import '../relay_failure.dart';
import '../transport/nostr_transport.dart';
import 'relay_connection_key.dart';
import 'relay_connectivity.dart';
import 'relay_revivals.dart';
import 'request_slots.dart';
import 'socket_limits.dart';

/// A connection of `RelayConnections`. Internal to dostr_core.
///
/// Only `RelayConnections` and the parts it owns change it. Everyone else sees
/// its [snapshot].
class RelayConnection {
  final RelayConnectionKey key;

  final ConnectAttempts attempts = ConnectAttempts();

  /// the REQs holding a slot on the current socket
  final RequestSlots slots = RequestSlots();

  /// what the relay reads on the current socket
  SocketLimits limits = SocketLimits.none();

  /// the current socket, null while it neither is connected nor connecting
  NostrTransport? relayTransport;

  StreamSubscription? _streamSubscription;

  /// time since a message went through, a socket was tried, or the connection
  /// was last found with work, which the idle timeouts read
  final Stopwatch idleFor = Stopwatch()..start();

  /// the signer of a bound connection, kept because a challenge can arrive
  /// long after whatever asked for that identity is gone
  NostrSigner? account;

  /// NIP-42 on the current socket, opened by `RelayAuth.sessionOf`
  AuthSession? authSession;

  /// the opening of a socket under way, which completes with why it failed
  Future<RelayFailure?>? opening;

  /// the bringing back of a connection whose socket dropped, owned by
  /// `RelayRevivals`
  Revival? revival;

  RelayConnection(this.key, {this.relayTransport});

  RelayUrl get url => key.url;

  bool get isConnected => relayTransport?.isOpen ?? false;

  /// The connection as it stands now, which nothing changes afterwards.
  RelayConnectivity snapshot() => _ConnectivitySnapshot(
    key: key,
    isConnected: isConnected,
    isConnecting: attempts.connecting,
  );

  /// whether the relay accepted an AUTH on the current socket
  bool get isAuthenticated => authSession?.authenticated ?? false;

  bool get isAuthenticating => authSession?.authenticating ?? false;

  void listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) {
    _streamSubscription = relayTransport!.listen(
      onData,
      onDone: onDone,
      onError: onError,
    );
  }

  /// Retires the current socket right away, and completes once it is closed.
  /// Never throws.
  Future<void> close() {
    final streamSubscription = _streamSubscription;
    final transport = relayTransport;

    _streamSubscription = null;
    relayTransport = null;
    // the socket carried them, they die with it
    authSession?.end();
    authSession = null;
    slots.clear();

    return _retire(streamSubscription, transport);
  }

  Future<void> _retire(
    StreamSubscription? streamSubscription,
    NostrTransport? transport,
  ) async {
    try {
      final cancelled = streamSubscription?.cancel();
      final closed = transport?.close();
      await cancelled;
      await closed?.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          logger.warning(() => "timeout while trying to close socket $url");
        },
      );
    } catch (error) {
      logger.warning(() => "Error closing the socket of $url: $error");
    }
  }
}

/// The connection attempts of a [RelayConnection].
class ConnectAttempts {
  bool connecting = false;

  DateTime? _lastFailure;

  void tryingToConnect() {
    connecting = true;
  }

  void succeededToConnect() {
    _lastFailure = null;
    connecting = false;
  }

  void failedToConnect() {
    _lastFailure = DateTime.now();
    connecting = false;
  }

  /// Whether its last attempt failed less than [duration] ago.
  bool failedWithin(Duration duration) {
    final failure = _lastFailure;
    return failure != null && DateTime.now().difference(failure) < duration;
  }
}

final class _ConnectivitySnapshot implements RelayConnectivity {
  @override
  final RelayConnectionKey key;

  @override
  final bool isConnected;

  @override
  final bool isConnecting;

  const _ConnectivitySnapshot({
    required this.key,
    required this.isConnected,
    required this.isConnecting,
  });

  @override
  String toString() =>
      "$key: ${isConnected ? 'connected' : (isConnecting ? 'connecting' : 'disconnected')}";
}
