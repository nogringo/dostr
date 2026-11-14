import 'dart:async';
import 'dart:collection';

import 'package:dostr_nip01/dostr_nip01.dart';
import '../../entities/relay.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_connectivity.dart';
import '../../entities/relay_stats.dart';
import '../../repositories/nostr_transport.dart';
import '../../../shared/logger/logger.dart';

/// A connection of `RelayConnections`, which alone changes it. Internal to
/// dostr_core: everyone else sees a [RelayConnectivity].
class RelayConnection implements RelayConnectivity {
  @override
  final RelayConnectionKey key;

  @override
  final MutableRelay relay;

  @override
  final MutableRelayStats stats = MutableRelayStats();

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
  /// the write it waits for, see [MutableRelayStats.openRequestIds] for the
  /// written ones
  final Map<String, Object> reservedRequestIds = {};

  RelayConnection(this.key, {this.relayTransport})
    : relay = MutableRelay(url: key.url);

  @override
  String get url => key.url;

  @override
  bool get isConnected => relayTransport?.isOpen() ?? false;

  /// Whether the REQ [id] holds a slot here, written or not.
  bool holdsSlot(String id) =>
      stats.openRequestIds.contains(id) || reservedRequestIds.containsKey(id);

  /// ids of every REQ holding a slot here
  Set<String> get heldSlots => {
    ...stats.openRequestIds,
    ...reservedRequestIds.keys,
  };

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

  /// cancels stream subscription and closes relay transport
  Future<void> close() async {
    final streamSubscription = _streamSubscription;
    final transport = relayTransport;

    _streamSubscription = null;
    relayTransport = null;
    // the socket carried them, they die with it
    stats.openRequestIds.clear();
    reservedRequestIds.clear();
    longestMessage = 0;

    if (streamSubscription != null) {
      await streamSubscription.cancel();
    }
    if (transport != null) {
      await transport.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Logger.log.w(() => "timeout while trying to close socket $url");
        },
      );
    }
  }
}

/// The [Relay] of a [RelayConnection].
class MutableRelay implements Relay {
  @override
  final String url;

  @override
  bool connecting = false;

  @override
  int? lastConnectTry;

  @override
  int? lastSuccessfulConnect;

  MutableRelay({required this.url});

  /// set trying to connect
  void tryingToConnect() {
    lastConnectTry = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    connecting = true;
  }

  /// mark as succeded to connect
  void succeededToConnect() {
    lastSuccessfulConnect = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    connecting = false;
  }

  /// mark as failed to connect
  void failedToConnect() {
    connecting = false;
  }

  @override
  bool wasLastConnectTryLongerThanSeconds(int seconds) {
    return lastConnectTry == null ||
        lastConnectTry! <
            DateTime.now()
                    .add(Duration(seconds: -seconds))
                    .millisecondsSinceEpoch ~/
                1000;
  }
}

/// The [RelayStats] of a [RelayConnection].
class MutableRelayStats implements RelayStats {
  @override
  int connections = 0;

  @override
  int connectionErrors = 0;

  /// ids of the requests open on the connection, so that a request replayed on
  /// a socket that came back is not counted twice and a CLOSE that lands late
  /// does not count below what is open
  final Set<String> openRequestIds = {};

  @override
  int get activeRequests => openRequestIds.length;

  final Map<int, int> _eventsRead = {};

  final Map<int, int> _dataReadBytes = {};

  @override
  Map<int, int> get eventsRead => UnmodifiableMapView(_eventsRead);

  @override
  Map<int, int> get dataReadBytes => UnmodifiableMapView(_dataReadBytes);

  @override
  int getTotalEventsRead() => _eventsRead.values.fold(0, (a, b) => a + b);

  @override
  int getTotalBytesRead() => _dataReadBytes.values.fold(0, (a, b) => a + b);

  /// increment stats by new event
  void incStatsByNewEvent(Nip01Event event, int bytes) {
    _eventsRead[event.kind] = (_eventsRead[event.kind] ?? 0) + 1;
    _dataReadBytes[event.kind] = (_dataReadBytes[event.kind] ?? 0) + bytes;
  }
}
