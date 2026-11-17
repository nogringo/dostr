import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A relay on the VM for websocket_client_transport_browser_test.dart. It sends
/// its URL, then "hung up" each time a client goes away.
Future<void> hybridMain(dynamic channel, Object? mode) async {
  void hungUp([Object? _]) => channel.sink.add('hung up');

  switch (mode) {
    case 'refused':
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      channel.sink.add('ws://127.0.0.1:$port');
    case 'silent':
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(
        (socket) => socket.listen((_) {}, onDone: hungUp, onError: hungUp),
      );
      channel.sink.add('ws://127.0.0.1:${server.port}');
    case 'echo':
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          if (message == 'close me') {
            socket.close(WebSocketStatus.messageTooBig, 'too big');
          } else {
            socket.add(message);
          }
        }, onDone: hungUp);
      });
      channel.sink.add('ws://127.0.0.1:${server.port}');
    case 'bad frame':
      // answers the handshake, then sends a frame with a reserved bit set,
      // which makes the browser fail the connection after it opened
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final key = request.headers.value('sec-websocket-key')!;
        request.response
          ..statusCode = HttpStatus.switchingProtocols
          ..headers.set('connection', 'Upgrade')
          ..headers.set('upgrade', 'websocket')
          ..headers.set(
            'sec-websocket-accept',
            base64.encode(
              sha1
                  .convert(
                    utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
                  )
                  .bytes,
            ),
          );
        final socket = await request.response.detachSocket();
        socket.listen((_) {}, onDone: hungUp, onError: hungUp);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        socket.add([0xc1, 0x00]);
      });
      channel.sink.add('ws://127.0.0.1:${server.port}');
  }
}
