import 'package:web_socket_channel/html.dart';

import '../../../domain_layer/repositories/nostr_transport.dart';
import 'websocket_client_nostr_transport.dart';

/// Browsers handle compression and keep-alive themselves, so [pingInterval]
/// and [compressionEnabled] have no effect here.
NostrTransport connectWebSocket(
  Uri uri, {
  required Duration? pingInterval,
  required bool compressionEnabled,
}) {
  final channel = HtmlWebSocketChannel.connect(
    uri,
    binaryType: BinaryType.list,
  );
  return WebSocketClientNostrTransport(
    channel,
    abortHandshake: () => channel.innerWebSocket.close(),
  );
}
