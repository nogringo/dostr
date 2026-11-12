import 'package:dostr_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport.dart';
import '../../../src/web_socket_client/web_socket_client.dart';

import '../../../domain_layer/repositories/nostr_transport.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import '../../data_sources/websocket_client.dart';

class WebSocketClientNostrTransportFactory implements NostrTransportFactory {
  WebSocketClientNostrTransportFactory({
    this.compressionEnabled = true,
    this.pingInterval = const Duration(seconds: 10),
  }) {
    if (pingInterval != null && pingInterval! <= Duration.zero) {
      throw ArgumentError.value(
        pingInterval,
        'pingInterval',
        'must be positive',
      );
    }
  }

  final Duration? pingInterval;

  final bool compressionEnabled;

  @override
  NostrTransport call(String url) {
    final myUrl = cleanRelayUrl(url);

    if (myUrl == null) {
      throw Exception("relayUrl is not parsable");
    }

    final client = WebSocket(
      Uri.parse(myUrl),
      reconnect: false,
      pingInterval: pingInterval,
      binaryType: 'arraybuffer',
      compressionEnabled: compressionEnabled,
    );

    final WebsocketDSClient myDataSource = WebsocketDSClient(client, myUrl);
    return WebSocketClientNostrTransport(myDataSource);
  }
}
