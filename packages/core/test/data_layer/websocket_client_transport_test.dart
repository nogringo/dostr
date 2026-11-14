@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:dostr_core/src/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:test/test.dart';

const _wait = Duration(seconds: 2);

void main() {
  final factory = WebSocketClientNostrTransportFactory(pingInterval: null);

  test('ready fails with the reason a connection was refused', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();

    final transport = factory('ws://127.0.0.1:$port');
    addTearDown(transport.close);

    await expectLater(
      transport.ready.timeout(_wait),
      throwsA(isA<SocketException>()),
    );
  });

  test(
    'closing before the handshake is answered fails ready and hangs up',
    () async {
      // accepts the TCP connection and never answers the handshake
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      silent.listen(accepted.complete);
      addTearDown(silent.close);

      final transport = factory('ws://127.0.0.1:${silent.port}');
      final ready = transport.ready;
      final socket = await accepted.future.timeout(_wait);
      addTearDown(socket.destroy);
      final hungUp = socket.drain<void>().catchError((_) {});
      await transport.close();

      await expectLater(ready.timeout(_wait), throwsA(isA<StateError>()));
      await hungUp.timeout(_wait);
      expect(transport.isConnecting(), isFalse);
    },
  );

  test('a dropped socket ends the transport for good', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var connections = 0;
    server.listen((request) async {
      connections++;
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.close();
    });
    addTearDown(() => server.close(force: true));

    final transport = factory('ws://127.0.0.1:${server.port}');
    addTearDown(transport.close);
    final ended = Completer<void>();
    transport.listen((_) {}, onDone: ended.complete);

    await transport.ready.timeout(_wait);
    await ended.future.timeout(_wait);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(transport.isOpen(), isFalse);
    expect(connections, 1);
  });

  test('tells the close code and reason the relay sent', () async {
    final relay = await _EchoRelay.start();
    addTearDown(relay.close);
    final upgraded = relay.nextSocket;
    final transport = factory(relay.url);
    addTearDown(transport.close);
    final ended = Completer<void>();
    transport.listen((_) {}, onDone: ended.complete);
    await transport.ready.timeout(_wait);

    await (await upgraded).close(WebSocketStatus.messageTooBig, 'too big');
    await ended.future.timeout(_wait);

    expect(transport.closeCode(), WebSocketStatus.messageTooBig);
    expect(transport.closeReason(), 'too big');
    expect(transport.isOpen(), isFalse);
  });

  test('closing an open transport hangs up and ends its listeners', () async {
    final relay = await _EchoRelay.start();
    addTearDown(relay.close);
    final transport = factory(relay.url);
    final ended = Completer<void>();
    transport.listen((_) {}, onDone: ended.complete);
    await transport.ready.timeout(_wait);

    final hungUp = relay.nextHangUp;
    await transport.close();

    await ended.future.timeout(_wait);
    await hungUp.timeout(_wait);
    expect(transport.isOpen(), isFalse);
    expect(transport.isConnecting(), isFalse);
  });

  test('the handshake sends the configured user agent', () async {
    final relay = await _EchoRelay.start();
    addTearDown(relay.close);
    final previous = WebSocket.userAgent;
    WebSocket.userAgent = 'dostr transport test';
    addTearDown(() => WebSocket.userAgent = previous);

    final transport = factory(relay.url);
    addTearDown(transport.close);
    await transport.ready.timeout(_wait);

    expect(
      relay.headers.single.value(HttpHeaders.userAgentHeader),
      'dostr transport test',
    );
  });

  for (final compressionEnabled in [true, false]) {
    test('echoes text and bytes with compression '
        '${compressionEnabled ? 'on' : 'off'}', () async {
      final relay = await _EchoRelay.start();
      addTearDown(relay.close);
      final transport = WebSocketClientNostrTransportFactory(
        pingInterval: null,
        compressionEnabled: compressionEnabled,
      )(relay.url);
      addTearDown(transport.close);
      final received = <dynamic>[];
      final echoed = Completer<void>();
      transport.listen((message) {
        received.add(message);
        if (received.length == 2) echoed.complete();
      });
      await transport.ready.timeout(_wait);

      transport.send('text');
      transport.send([1, 2, 3]);
      await echoed.future.timeout(_wait);

      expect(received, [
        'text',
        [1, 2, 3],
      ]);
      final deflate = compressionEnabled
          ? contains('permessage-deflate')
          : isNull;
      expect(relay.headers.single.value('sec-websocket-extensions'), deflate);
      expect(relay.negotiated.single, deflate);
    });
  }
}

/// Accepts every WebSocket and echoes what it receives.
class _EchoRelay {
  final HttpServer _server;
  final headers = <HttpHeaders>[];
  final negotiated = <String?>[];
  final _sockets = <WebSocket>[];
  final _upgraded = StreamController<WebSocket>.broadcast();
  final _hungUp = StreamController<void>.broadcast();

  _EchoRelay._(this._server) {
    _server.listen((request) async {
      headers.add(request.headers);
      final socket = await WebSocketTransformer.upgrade(
        request,
        compression: CompressionOptions.compressionDefault,
      );
      negotiated.add(
        request.response.headers.value('sec-websocket-extensions'),
      );
      _sockets.add(socket);
      socket.listen(socket.add, onDone: () => _hungUp.add(null));
      _upgraded.add(socket);
    });
  }

  static Future<_EchoRelay> start() async =>
      _EchoRelay._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String get url => 'ws://127.0.0.1:${_server.port}';

  Future<WebSocket> get nextSocket => _upgraded.stream.first;

  Future<void> get nextHangUp => _hungUp.stream.first;

  Future<void> close() async {
    for (final socket in _sockets) {
      await socket.close().timeout(_wait, onTimeout: () {});
    }
    await _server.close(force: true);
  }
}
