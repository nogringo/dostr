import 'dart:async';

import '../../../src/web_socket_client/web_socket_client.dart';

import '../../../domain_layer/repositories/nostr_transport.dart';
import '../../../src/logger/logger.dart';
import '../../data_sources/websocket_client.dart';

/// A [NostrTransport] over the vendored WebSocket client, which must be
/// created with `reconnect: false`.
class WebSocketClientNostrTransport implements NostrTransport {
  /// The underlying WebSocket data source.
  final WebsocketDSClient _websocketDS;
  late final StreamSubscription<ConnectionState> _stateStreamSubscription;
  final Completer<void> _ready = Completer<void>();

  /// Creates a new WebSocketClientNostrTransport instance.
  ///
  /// [_websocketDS] is the WebSocket data source to be used for communication.
  WebSocketClientNostrTransport(this._websocketDS) {
    // a socket that fails before anyone waits for it must not raise
    _ready.future.ignore();
    _stateStreamSubscription = _websocketDS.ws.connection.listen((state) {
      Logger.log.d(
        () => "${_websocketDS.url} connection state changed to $state",
      );
      switch (state) {
        case Connected() || Reconnected():
          if (!_ready.isCompleted) _ready.complete();
        case Disconnected():
          _failReady(
            state.error ??
                StateError("closed with ${state.code} ${state.reason}"),
          );
        case Connecting() || Reconnecting() || Disconnecting():
          break;
      }
    });
  }

  @override
  Future<void> get ready => _ready.future;

  void _failReady(Object error) {
    if (!_ready.isCompleted) _ready.completeError(error);
  }

  /// Closes the WebSocket connection.
  ///
  /// Returns a Future that completes when the connection has been closed.
  @override
  Future<void> close() async {
    _failReady(StateError("closed before it opened"));
    await _stateStreamSubscription.cancel();
    return _websocketDS.close();
  }

  /// Listens for data on the WebSocket connection.
  ///
  /// [onData] is called whenever data is received.
  /// [onError] is called if an error occurs (optional).
  /// [onDone] is called when the stream is closed (optional).
  ///
  /// Returns a StreamSubscription that can be used to control the subscription.
  @override
  StreamSubscription listen(
    void Function(dynamic p1) onData, {
    Function? onError,
    void Function()? onDone,
  }) {
    return _websocketDS.listen(onData, onError: onError, onDone: onDone);
  }

  /// Sends data through the WebSocket connection.
  ///
  /// [data] is the data to be sent.
  @override
  void send(data) {
    _websocketDS.send(data);
  }

  /// Checks if the WebSocket connection is currently open.
  ///
  /// Returns true if the connection is open, false otherwise.
  @override
  bool isOpen() {
    return _websocketDS.isOpen();
  }

  /// Checks if the WebSocket connection is currently open.
  ///
  /// Returns true if the connection is open, false otherwise.
  @override
  bool isConnecting() {
    return _websocketDS.isConnecting();
  }

  /// Gets the close code of the WebSocket connection.
  ///
  /// Returns the close code if the connection has been closed, null otherwise.
  @override
  int? closeCode() {
    return _websocketDS.closeCode();
  }

  /// Gets the close reason of the WebSocket connection.
  ///
  /// Returns the close reason if the connection has been closed, null otherwise.
  @override
  String? closeReason() {
    return _websocketDS.closeReason();
  }
}
