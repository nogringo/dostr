import 'dart:async';
import 'dart:collection';

import 'package:ndk_nip01/ndk_nip01.dart';
import '../domain_layer/entities/relay.dart';
import '../domain_layer/entities/relay_connection_key.dart';
import '../domain_layer/entities/relay_connectivity.dart';
import '../domain_layer/entities/relay_stats.dart';
import '../domain_layer/repositories/nostr_transport.dart';
import '../shared/logger/logger.dart';

/// A connection of `RelayConnections`, which alone changes it. Internal to
/// ndk_core: everyone else sees a [RelayConnectivity].
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

  RelayConnection(this.key, {this.relayTransport})
    : relay = MutableRelay(url: key.url);

  @override
  String get url => key.url;

  @override
  bool get isConnected => relayTransport?.isOpen() ?? false;

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
