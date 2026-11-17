import 'package:dostr_relay_url/dostr_relay_url.dart';

import '../../../domain_layer/repositories/nostr_transport.dart';
import 'web_socket_connect.dart'
    if (dart.library.io) 'web_socket_connect_io.dart'
    if (dart.library.js_interop) 'web_socket_connect_web.dart';

/// Opens each transport as a WebSocket.
///
/// On native platforms, [pingInterval] keeps the sockets alive, null sends no
/// ping, and [compressionEnabled] negotiates `permessage-deflate`. Browsers
/// handle both themselves.
NostrTransportFactory webSocketTransportFactory({
  bool compressionEnabled = true,
  Duration? pingInterval = const Duration(seconds: 10),
}) {
  if (pingInterval != null && pingInterval <= Duration.zero) {
    throw ArgumentError.value(pingInterval, 'pingInterval', 'must be positive');
  }
  return (RelayUrl url) => connectWebSocket(
    Uri.parse(url),
    pingInterval: pingInterval,
    compressionEnabled: compressionEnabled,
  );
}
