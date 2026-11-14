import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../domain_layer/repositories/nostr_transport.dart';

/// A [NostrTransport] over one [WebSocketChannel].
class WebSocketClientNostrTransport implements NostrTransport {
  /// [abortHandshake] stops a connection attempt that has not opened yet.
  WebSocketClientNostrTransport(
    this._channel, {
    void Function()? abortHandshake,
  }) : _abortHandshake = abortHandshake {
    // a socket that fails before anyone waits for it must not raise
    _ready.future.ignore();
    _channel.ready.then((_) {
      if (_ended) return;
      _open = true;
      _ready.complete();
    }, onError: (Object error) => _end(_unwrap(error)));
    _source = _channel.stream.listen(
      _messages.add,
      onError: (Object error) => _end(_unwrap(error)),
      onDone: () =>
          _end(StateError("closed with ${closeCode()} ${closeReason()}")),
    );
  }

  final WebSocketChannel _channel;
  final void Function()? _abortHandshake;
  final _ready = Completer<void>();
  final _messages = StreamController<dynamic>.broadcast();
  late final StreamSubscription<dynamic> _source;
  bool _open = false;
  bool _ended = false;

  static Object _unwrap(Object error) =>
      error is WebSocketChannelException ? error.inner ?? error : error;

  void _end(Object reason) {
    if (_ended) return;
    _ended = true;
    _open = false;
    if (!_ready.isCompleted) _ready.completeError(reason);
    unawaited(_source.cancel());
    _messages.close();
  }

  @override
  Future<void> get ready => _ready.future;

  @override
  bool isOpen() => _open;

  @override
  bool isConnecting() => !_open && !_ended;

  @override
  Future<void> close() async {
    if (!_open) _abortHandshake?.call();
    _end(StateError("closed before it opened"));
    // completes only once a socket received the close, which an aborted
    // handshake never opens
    _channel.sink.close().ignore();
  }

  @override
  StreamSubscription listen(
    void Function(dynamic p1) onData, {
    Function? onError,
    void Function()? onDone,
  }) => _messages.stream.listen(onData, onError: onError, onDone: onDone);

  @override
  void send(data) {
    if (_open) _channel.sink.add(data);
  }

  @override
  int? closeCode() => _channel.closeCode;

  @override
  String? closeReason() => _channel.closeReason;
}
