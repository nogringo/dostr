import 'package:dostr_url_set/dostr_url_set.dart';

import '../../../domain_layer/repositories/nostr_transport.dart';
import 'web_socket_connect.dart'
    if (dart.library.io) 'web_socket_connect_io.dart'
    if (dart.library.js_interop) 'web_socket_connect_web.dart';

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

    return connectWebSocket(
      Uri.parse(myUrl),
      pingInterval: pingInterval,
      compressionEnabled: compressionEnabled,
    );
  }
}
