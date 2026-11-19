@TestOn('browser')
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:dostr_noble/src/nostr_crypto_js.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

// The browser cannot compile Dart: the VM side of the test compiles the worker.
Future<String> _compileWorker() async {
  final channel = spawnHybridCode(r'''
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final dir = await Directory.systemTemp.createTemp('dostr_noble_worker');
  try {
    final output = '${dir.path}/worker.js';
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile', 'js', '-o', output, 'test/worker/signer_worker.dart',
    ]);
    if (result.exitCode != 0) {
      throw StateError('${result.stdout}${result.stderr}');
    }
    channel.sink.add(File(output).readAsStringSync());
  } finally {
    await dir.delete(recursive: true);
  }
}
''');
  return await channel.stream.first as String;
}

String _blobUrl(String script) =>
    web.URL.createObjectURL(web.Blob([script.toJS].toJS));

Future<String> _runWorker(String script) {
  final reply = Completer<String>();
  final worker = web.Worker(_blobUrl(script).toJS)
    ..onmessage = (web.MessageEvent event) {
      reply.complete((event.data as JSString).toDart);
    }.toJS
    ..onerror = (web.ErrorEvent event) {
      reply.completeError(StateError('The worker failed: ${event.message}'));
    }.toJS;
  return reply.future.whenComplete(() => worker.terminate());
}

void main() {
  late String worker;

  setUpAll(() async => worker = await _compileWorker());

  test('a worker that loaded the bundle signs', () async {
    expect(
      await _runWorker("importScripts('${_blobUrl(nostrCryptoJs)}');\n$worker"),
      '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
    );
  });

  test(
    'a worker that did not load it throws a StateError that says so',
    () async {
      expect(
        await _runWorker(worker),
        allOf(startsWith('StateError'), contains('importScripts')),
      );
    },
  );
}
