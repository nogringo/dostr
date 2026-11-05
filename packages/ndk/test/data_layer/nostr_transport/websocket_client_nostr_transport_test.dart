@TestOn('vm')
library;

import 'dart:io';

import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:test/test.dart';

void main() {
  test('a refused connection fails ready with its error', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();

    final transport = WebSocketClientNostrTransportFactory().call(
      'ws://127.0.0.1:$port',
    );
    addTearDown(transport.close);

    await expectLater(
      transport.ready.timeout(const Duration(seconds: 2)),
      throwsA(isA<SocketException>()),
    );
  });
}
