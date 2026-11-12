@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:dostr_nip11/dostr_nip11.dart';
import 'package:test/test.dart';

/// Keep production HTTPS mapping while routing test requests to local HTTP.
/// Request abortion uses the real IOClient.
class _LoopbackClient extends http.BaseClient {
  final IOClient inner = IOClient();
  bool closed = false;
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final trigger = (request as http.Abortable).abortTrigger!;
    unawaited(trigger.then((_) => aborted = true));
    final local = http.AbortableRequest(
      request.method,
      request.url.replace(scheme: 'http'),
      abortTrigger: trigger,
    )..headers.addAll(request.headers);
    return inner.send(local);
  }

  @override
  void close() {
    closed = true;
    inner.close();
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('socket remained open');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  for (final scenario in [('headers', true, false), ('body', true, true)]) {
    test(
      'timeout closes native socket when ${scenario.$1} never finishes',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final connected = Completer<void>();
        final peerClosed = Completer<void>();
        Socket? peer;
        server.listen((socket) {
          peer = socket;
          socket.listen(
            (data) {
              if (!connected.isCompleted) {
                connected.complete();
                if (scenario.$3) {
                  socket.write(
                    'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n',
                  );
                }
              }
            },
            onDone: () {
              if (!peerClosed.isCompleted) peerClosed.complete();
            },
          );
        });
        final client = _LoopbackClient();
        addTearDown(() async {
          client.close();
          peer?.destroy();
          await server.close();
        });
        final result = HttpRelayInfoRepo(
          client,
          timeout: const Duration(milliseconds: 300),
        ).getRelayInfo('wss://127.0.0.1:${server.port}');
        await connected.future.timeout(const Duration(seconds: 2));
        await expectLater(result, throwsA(isA<TimeoutException>()));
        await _waitUntil(() => client.aborted);
        await peerClosed.future.timeout(const Duration(seconds: 2));
      },
    );
  }

  test('valid response is decoded as UTF-8 nostr+json', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.headers.value('Accept'), 'application/nostr+json');
      request.response.write(
        jsonEncode({
          'name': 'Test relay ⚡',
          'supported_nips': [1, 11],
        }),
      );
      await request.response.close();
    });
    final client = _LoopbackClient();
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    final info = await HttpRelayInfoRepo(
      client,
    ).getRelayInfo('wss://127.0.0.1:${server.port}');
    expect(info?.name, 'Test relay ⚡');
    expect(info?.supportsNip('11'), isTrue);
    expect(client.aborted, isFalse);
  });

  test('a ws relay serves its document over http', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write(jsonEncode({'name': 'Local relay'}));
      await request.response.close();
    });
    final client = IOClient();
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    final info = await HttpRelayInfoRepo(
      client,
    ).getRelayInfo('ws://127.0.0.1:${server.port}');
    expect(info?.name, 'Local relay');
  });

  test('malformed response returns null', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write('invalid json');
      await request.response.close();
    });
    final client = _LoopbackClient();
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    final info = await HttpRelayInfoRepo(
      client,
    ).getRelayInfo('wss://127.0.0.1:${server.port}');
    expect(info, isNull);
  });
}
