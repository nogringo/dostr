import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:ndk/ndk.dart';
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

void main() {
  test('destroying Ndk aborts an unawaited relay info fetch and keeps the '
      'shared client open', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <Socket>[];
    server.listen(peers.add);
    final client = _LoopbackClient();
    addTearDown(() async {
      client.close();
      for (final peer in peers) {
        peer.destroy();
      }
      await server.close();
    });
    final ndk = http.runWithClient(
      Ndk.emptyBootstrapRelaysConfig,
      () => client,
    );

    final info = ndk.connectivity.getRelayInfo(
      'wss://127.0.0.1:${server.port}',
    );
    await ndk.destroy();

    // the relay never answers, so only destroy can settle the fetch before
    // the 5s repo timeout
    expect(await info.timeout(const Duration(seconds: 1)), isNull);
    expect(client.aborted, isTrue);
    expect(client.closed, isFalse);
  });
}
