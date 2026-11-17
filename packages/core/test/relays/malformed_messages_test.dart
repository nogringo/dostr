import 'dart:async';
import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/protocol.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

class _Transport implements NostrTransport {
  final controller = StreamController<dynamic>();
  final sent = <String>[];

  @override
  Future<void> ready = Future.value();
  @override
  bool get isOpen => true;
  @override
  Future<void> close() async {}
  @override
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    Function()? onDone,
  }) => controller.stream.listen(onData, onError: onError, onDone: onDone);
  @override
  void send(dynamic data) => sent.add(data);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
}

class _Factory {
  late _Transport last;

  NostrTransport call(String url) => last = _Transport();
}

class _ThrowingHandler extends RelayProtocolHandler {
  @override
  bool onMessage(RelayConnectionKey key, List<dynamic> message) =>
      throw StateError('handler bug');

  @override
  void onNotice(RelayConnectionKey key, String message) =>
      throw StateError('handler bug');
}

void main() {
  final url = RelayUrl.parse('wss://relay.example.com');
  late _Factory factory;
  late RelayManager manager;

  setUp(() async {
    factory = _Factory();
    manager = RelayManager(nostrTransportFactory: factory.call);
    await manager.connectRelay(url);
  });

  tearDown(() => manager.dispose());

  /// Whether a query sent after whatever the relay sent so far still ends on
  /// the EOSE that relay sends next.
  Future<void> expectStillServed() async {
    final reqs = RelayReqs(
      relayManager: manager,
      eventVerifier: FakeVerifier(),
    );
    final req = reqs.req(
      relays: {
        url: [
          Filter(kinds: [1]),
        ],
      },
    );
    await eventually(
      () => factory.last.sent.any((sent) => sent.contains(req.id)),
    );
    factory.last.controller.add(jsonEncode(['EOSE', req.id]));

    expect(await req.done, {
      url: const RelayRequestOutcome(RelayRequestStatus.eose),
    });
  }

  test('a relay sending malformed messages keeps being served', () async {
    for (final frame in [
      'not json',
      '{}',
      '[]',
      '[1]',
      '["OK"]',
      '["OK",1,true]',
      '["OK","id","yes"]',
      '["OK","id",true,5]',
      '["EOSE"]',
      '["EOSE",1]',
      '["NOTICE"]',
      '["NOTICE",{}]',
      '["CLOSED"]',
      '["CLOSED","sub",5]',
      '["AUTH"]',
      '["AUTH",5]',
      '["EVENT"]',
      '["EVENT",null,{}]',
      '["EVENT","sub",{"id":"x"}]',
    ]) {
      factory.last.controller.add(frame);
    }
    factory.last.controller.add(<int>[1, 2, 3]);

    await expectStillServed();
  });

  test('a protocol handler that throws does not stop the messages', () async {
    manager.addProtocolHandler(_ThrowingHandler());

    factory.last.controller
      ..add('["NEG-MSG","sub","00"]')
      ..add('["NOTICE","hello"]');

    await expectStillServed();
  });
}
