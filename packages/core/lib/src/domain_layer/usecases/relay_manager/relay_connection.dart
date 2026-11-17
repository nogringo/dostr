import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../shared/logger.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_connectivity.dart';
import '../../entities/relay_failure.dart';
import '../../repositories/nostr_transport.dart';
import 'auth_session.dart';
import 'relay_revivals.dart';

/// A connection of `RelayConnections`, which alone changes it. Internal to
/// dostr_core: everyone else sees its [snapshot].
class RelayConnection {
  final RelayConnectionKey key;

  final ConnectAttempts attempts = ConnectAttempts();

  /// ids of the REQs open on the connection, so that a request replayed on a
  /// socket that came back is not counted twice and a CLOSE that lands late
  /// does not count below what is open
  final Set<String> openRequestIds = {};

  /// transport layer for this relay, usually websocket, null while it neither
  /// is connected nor connecting
  NostrTransport? relayTransport;

  StreamSubscription? _streamSubscription;

  /// how many REQs the relay keeps open on this socket, null until known
  int? subscriptionLimit;

  /// how many UTF-8 bytes the relay reads in one message, as it publishes it,
  /// null when unknown
  int? messageLengthLimit;

  /// tells a late answer for a previous socket from the current one
  int limitsGeneration = 0;

  /// completes once [subscriptionLimit] and [messageLengthLimit] are settled
  /// for this socket
  Completer<void> limitsKnown = Completer()..complete();

  /// UTF-8 length of the longest message written on this socket
  int longestMessage = 0;

  /// time since a message went through, a socket was tried, or the connection
  /// was last found with work
  final Stopwatch idleFor = Stopwatch()..start();

  /// ids of the REQs that hold a slot here but are not written yet, each with
  /// the write it waits for, see [openRequestIds] for the written ones
  final Map<String, Object> reservedRequestIds = {};

  /// the signer a bound connection was opened as: a challenge can arrive long
  /// after whatever asked for that identity is gone
  NostrSigner? account;

  /// NIP-42 on the current socket, opened by `RelayAuth.sessionOf`
  AuthSession? authSession;

  /// the socket being opened, with why it could not be
  Future<RelayFailure?>? opening;

  /// the bringing back of a socket that dropped, see `RelayRevivals`
  Revival? revival;

  RelayConnection(this.key, {this.relayTransport});

  RelayUrl get url => key.url;

  bool get isConnected => relayTransport?.isOpen() ?? false;

  /// The connection as it stands now, which nothing changes afterwards.
  RelayConnectivity snapshot() => _ConnectivitySnapshot(
    key: key,
    isConnected: isConnected,
    isConnecting: attempts.connecting,
  );

  /// whether the relay accepted an AUTH on the current socket
  bool get isAuthenticated => authSession?.authenticated ?? false;

  bool get isAuthenticating => authSession?.authenticating ?? false;

  /// Whether the REQ [id] holds a slot here, written or not.
  bool holdsSlot(String id) =>
      openRequestIds.contains(id) || reservedRequestIds.containsKey(id);

  /// ids of every REQ holding a slot here
  Set<String> get heldSlots => {...openRequestIds, ...reservedRequestIds.keys};

  /// starts listening on nostr transport
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
    openRequestIds.clear();
    reservedRequestIds.clear();
    longestMessage = 0;

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
