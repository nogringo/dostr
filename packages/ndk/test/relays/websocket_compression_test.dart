import 'dart:async';
import 'dart:io';

import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

class _CompressionRelay {
  late final HttpServer _server;
  final Map<String, List<String?>> extensionOffers = {};
  final Map<String, List<WebSocket>> sockets = {};

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      // ndk also asks for the NIP-11 document of the relay
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final path = request.uri.path;
      extensionOffers
          .putIfAbsent(path, () => [])
          .add(request.headers.value('sec-websocket-extensions'));
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.putIfAbsent(path, () => []).add(socket);
      socket.listen(socket.add);
    });
  }

  String url(String path) => 'ws://localhost:${_server.port}$path';

  Future<void> close() async {
    for (final socket in sockets.values.expand((sockets) => sockets)) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  String reason = 'condition never became true',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(reason);
}

Ndk _createNdk(
  String relayUrl, {
  required NdkEngine engine,
  required bool compressionEnabled,
}) {
  return Ndk(
    NdkConfig(
      cache: MemCacheManager(),
      eventVerifier: Bip340EventVerifier(),
      bootstrapRelays: [relayUrl],
      engine: engine,
      webSocketCompression: compressionEnabled,
    ),
  );
}

void main() {
  group('WebSocket compression', () {
    late _CompressionRelay relay;

    setUp(() async {
      relay = _CompressionRelay();
      await relay.start();
    });

    tearDown(() => relay.close());

    test('NdkConfig preserves compression by default', () {
      final config = NdkConfig(
        cache: MemCacheManager(),
        eventVerifier: Bip340EventVerifier(),
      );

      expect(config.webSocketCompression, isTrue);
    });

    test('defaults on and supports opt-out', () async {
      final defaultTransport = WebSocketClientNostrTransportFactory()(
        relay.url('/default'),
      );
      final uncompressedTransport = WebSocketClientNostrTransportFactory(
        compressionEnabled: false,
      )(relay.url('/uncompressed'));

      try {
        await Future.wait([
          defaultTransport.ready,
          uncompressedTransport.ready,
        ]);

        expect(
          relay.extensionOffers['/default']!.single,
          contains('permessage-deflate'),
        );
        expect(relay.extensionOffers['/uncompressed']!.single, isNull);

        final echo = Completer<dynamic>();
        final subscription = uncompressedTransport.listen((message) {
          if (!echo.isCompleted) echo.complete(message);
        });
        uncompressedTransport.send('uncompressed');
        expect(await echo.future, 'uncompressed');
        await subscription.cancel();
      } finally {
        await defaultTransport.close();
        await uncompressedTransport.close();
      }
    });

    test('keeps opt-out when a dropped connection comes back', () async {
      final url = relay.url('/uncompressed');
      final manager = RelayManager(
        nostrTransportFactory: WebSocketClientNostrTransportFactory(
          compressionEnabled: false,
        ),
      );

      try {
        expect((await manager.connectRelay(dirtyUrl: url)).connected, isTrue);

        await relay.sockets['/uncompressed']!.last.close();
        await _waitUntil(
          () => relay.extensionOffers['/uncompressed']!.length == 2,
          reason: 'the connection did not come back',
        );
        await _waitUntil(
          () => manager.isRelayConnected(url),
          reason: 'the connection that came back did not open',
        );
        expect(relay.extensionOffers['/uncompressed'], everyElement(isNull));
      } finally {
        await manager.closeAllTransports();
      }
    });

    for (final engine in NdkEngine.values) {
      test(
        'NdkConfig opt-out reaches ${engine.name} relay connections',
        () async {
          final path = '/${engine.name.toLowerCase()}';
          final ndk = _createNdk(
            relay.url(path),
            engine: engine,
            compressionEnabled: false,
          );

          try {
            await ndk.bootstrapRelaysConnected;
            expect(relay.extensionOffers[path], everyElement(isNull));
          } finally {
            await ndk.destroy();
          }
        },
      );
    }

    test('compression setting remains instance-local', () async {
      final compressed = _createNdk(
        relay.url('/compressed-instance'),
        engine: NdkEngine.RELAY_SETS,
        compressionEnabled: true,
      );
      final uncompressed = _createNdk(
        relay.url('/uncompressed-instance'),
        engine: NdkEngine.RELAY_SETS,
        compressionEnabled: false,
      );

      try {
        await Future.wait([
          compressed.bootstrapRelaysConnected,
          uncompressed.bootstrapRelaysConnected,
        ]);
        expect(
          relay.extensionOffers['/compressed-instance']!.single,
          contains('permessage-deflate'),
        );
        expect(relay.extensionOffers['/uncompressed-instance']!.single, isNull);
      } finally {
        await compressed.destroy();
        await uncompressed.destroy();
      }
    });
  });
}
