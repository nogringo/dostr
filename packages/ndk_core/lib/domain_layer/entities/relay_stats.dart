/// What a `RelayConnectivity` carried, counted by its `RelayManager`.
abstract interface class RelayStats {
  /// number of connections
  int get connections;

  /// number of connection errors
  int get connectionErrors;

  /// number of active requests on this relay
  int get activeRequests;

  /// kind as keys, count as values
  Map<int, int> get eventsRead;

  /// kind as keys, bytes amount as values
  Map<int, int> get dataReadBytes;

  /// Get total number of read events in this relay
  int getTotalEventsRead();

  /// Get total bytes read this relay
  int getTotalBytesRead();
}
