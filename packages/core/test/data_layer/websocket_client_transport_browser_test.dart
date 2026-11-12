@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dostr_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:test/test.dart';

const _wait = Duration(seconds: 5);

void main() {
  final factory = WebSocketClientNostrTransportFactory();

  /// Starts browser_relay.dart in [mode], and returns its URL and what it says
  /// after that.
  Future<(String, StreamIterator<dynamic>)> relay(String mode) async {
    final events = StreamIterator(
      spawnHybridUri('browser_relay.dart', message: mode).stream,
    );
    await events.moveNext();
    return (events.current as String, events);
  }

  Future<void> hangUp(StreamIterator<dynamic> events) async {
    expect(await events.moveNext().timeout(_wait), isTrue);
    expect(events.current, 'hung up');
  }

  test('ready fails when the connection is refused', () async {
    final (url, _) = await relay('refused');
    final transport = factory(url);
    addTearDown(transport.close);

    await expectLater(transport.ready.timeout(_wait), throwsA(anything));
    expect(transport.isConnecting(), isFalse);
  });

  test(
    'closing before the handshake is answered fails ready and hangs up',
    () async {
      final (url, events) = await relay('silent');
      final transport = factory(url);
      final ready = transport.ready;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await transport.close();

      await expectLater(ready.timeout(_wait), throwsA(isA<StateError>()));
      await hangUp(events);
    },
  );

  test('echoes text, and bytes as a Uint8List', () async {
    final (url, _) = await relay('echo');
    final transport = factory(url);
    addTearDown(transport.close);
    final received = <dynamic>[];
    final echoed = Completer<void>();
    transport.listen((message) {
      received.add(message);
      if (received.length == 2) echoed.complete();
    });
    await transport.ready.timeout(_wait);

    transport.send('text');
    // a browser sends a plain List as text
    transport.send(Uint8List.fromList([1, 2, 3]));
    await echoed.future.timeout(_wait);

    expect(received, [
      'text',
      [1, 2, 3],
    ]);
    expect(received.last, isA<Uint8List>());
  });

  test('tells the close code and reason the relay sent', () async {
    final (url, _) = await relay('echo');
    final transport = factory(url);
    addTearDown(transport.close);
    final ended = Completer<void>();
    transport.listen((_) {}, onDone: ended.complete);
    await transport.ready.timeout(_wait);

    transport.send('close me');
    await ended.future.timeout(_wait);

    expect(transport.closeCode(), 1009);
    expect(transport.closeReason(), 'too big');
    expect(transport.isOpen(), isFalse);
  });

  test('closing an open transport hangs up and ends its listeners', () async {
    final (url, events) = await relay('echo');
    final transport = factory(url);
    final ended = Completer<void>();
    transport.listen((_) {}, onDone: ended.complete);
    await transport.ready.timeout(_wait);

    await transport.close();

    await ended.future.timeout(_wait);
    await hangUp(events);
    expect(transport.isOpen(), isFalse);
  });

  test('a connection that fails after it opened just ends', () async {
    final (url, _) = await relay('bad frame');
    final transport = factory(url);
    addTearDown(transport.close);
    final ended = Completer<void>();
    transport.listen((_) {}, onDone: ended.complete);
    await transport.ready.timeout(_wait);

    await ended.future.timeout(_wait);
    expect(transport.isOpen(), isFalse);
  });
}
