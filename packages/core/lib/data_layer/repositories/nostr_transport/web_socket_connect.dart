import '../../../domain_layer/repositories/nostr_transport.dart';

NostrTransport connectWebSocket(
  Uri uri, {
  required Duration? pingInterval,
  required bool compressionEnabled,
}) => throw UnsupportedError('WebSockets are not available on this platform');
