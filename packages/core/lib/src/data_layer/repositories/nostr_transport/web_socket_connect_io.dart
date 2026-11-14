import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../../../domain_layer/repositories/nostr_transport.dart';
import 'websocket_client_nostr_transport.dart';

NostrTransport connectWebSocket(
  Uri uri, {
  required Duration? pingInterval,
  required bool compressionEnabled,
}) {
  // A client per handshake, so closing it aborts a peer that never answers the
  // upgrade. The upgraded socket is detached from it and outlives it.
  final client = HttpClient()..userAgent = WebSocket.userAgent;
  final socket = WebSocket.connect(
    uri.toString(),
    customClient: client,
    compression: compressionEnabled
        ? CompressionOptions.compressionDefault
        : CompressionOptions.compressionOff,
  ).then((socket) => socket..pingInterval = pingInterval);
  socket.whenComplete(() => client.close(force: true)).ignore();
  return WebSocketClientNostrTransport(
    IOWebSocketChannel(socket),
    abortHandshake: () => client.close(force: true),
  );
}
