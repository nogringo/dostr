import 'dart:io';

/// Sets the User-Agent of the websockets of this process, through the global
/// `WebSocket.userAgent`. It has no effect on the web.
void configureDefaultUserAgent(String userAgent) {
  WebSocket.userAgent = userAgent;
}
