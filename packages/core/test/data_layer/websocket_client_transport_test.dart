@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:dostr_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:test/test.dart';

void main() {
  final factory = WebSocketClientNostrTransportFactory(pingInterval: null);

  test('ready fails with the reason a connection was refused', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();

    final transport = factory('ws://127.0.0.1:$port');
    addTearDown(transport.close);

    await expectLater(
      transport.ready.timeout(const Duration(seconds: 2)),
      throwsA(isA<SocketException>()),
    );
  });

  test('ready fails once the transport is closed before it opened', () async {
    // accepts the TCP connection and never answers the handshake
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    silent.listen(sockets.add);
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await silent.close();
    });

    final transport = factory('ws://127.0.0.1:${silent.port}');
    final ready = transport.ready;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await transport.close();

    await expectLater(
      ready.timeout(const Duration(seconds: 2)),
      throwsA(isA<StateError>()),
    );
  });

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

    await transport.ready.timeout(const Duration(seconds: 2));
    await ended.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(transport.isOpen(), isFalse);
    expect(connections, 1);
  });
}
