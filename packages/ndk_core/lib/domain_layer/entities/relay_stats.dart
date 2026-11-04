import 'nip_01_event.dart';

/// relay stats
class RelayStats {
  /// number of connections
  int connections = 0;

  /// number of connection errors
  int connectionErrors = 0;

  /// ids of the requests open on the connection, so that a request replayed on
  /// a socket that came back is not counted twice and a CLOSE that lands late
  /// does not count below what is open
  final Set<String> openRequestIds = {};

  /// number of active requests on this relay
  int get activeRequests => openRequestIds.length;

  /// kind as keys, count as values
  Map<int, int> eventsRead = {};

  /// kind as keys, count as values
  Map<int, int> eventsWritten = {};

  /// kind as keys, bytes amount as values
  Map<int, int> dataReadBytes = {};

  /// kind as keys, bytes amount as values
  Map<int, int> dataWrittenBytes = {};

  /// Get total number of read events in this relay
  int getTotalEventsRead() {
    return eventsRead.values.fold(0, (a, b) => a + b);
  }

  /// Get total bytes read this relay
  int getTotalBytesRead() {
    return dataReadBytes.values.fold(0, (a, b) => a + b);
  }

  /// increment stats by new event
  void incStatsByNewEvent(Nip01Event event, int bytes) {
    int eventsRead = this.eventsRead[event.kind] ?? 0;
    this.eventsRead[event.kind] = eventsRead + 1;
    int bytesRead = dataReadBytes[event.kind] ?? 0;
    dataReadBytes[event.kind] = bytesRead + bytes;
  }
}
