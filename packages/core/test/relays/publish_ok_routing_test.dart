import 'dart:async';
import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

/// A socket whose relay the test speaks for.
class _ScriptedTransport implements NostrTransport {
  final _incoming = StreamController<dynamic>();
  final sent = <List<dynamic>>[];

  void receive(List<dynamic> message) => _incoming.add(jsonEncode(message));

  bool hasSent(String type) => sent.any((message) => message.first == type);

  @override
  Future<void> get ready => Future.value();

  @override
  bool get isOpen => !_incoming.isClosed;

  @override
  Future<void> close() => _incoming.close();

  @override
  void send(dynamic data) => sent.add(jsonDecode(data as String) as List);

  @override
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) => _incoming.stream.listen(onData, onError: onError, onDone: onDone);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

void main() {
  final url = RelayUrl.parse('wss://relay.example.com');
  final sockets = <_ScriptedTransport>[];
  late RelayManager manager;
  late RelayPublishes publishes;

  setUp(() {
    sockets.clear();
    manager = RelayManager(
      nostrTransportFactory: (_) {
        final socket = _ScriptedTransport();
        sockets.add(socket);
        return socket;
      },
    );
    publishes = RelayPublishes(relayManager: manager);
  });

  tearDown(() => manager.dispose());

  test(
    'an auth-required on one connection leaves a publish on another waiting',
    () async {
      final event = signedEvent();
      final anonymous = publishes.publish(
        event,
        relays: [url],
        auth: const AuthPolicy.never(),
      );
      await eventually(
        () => sockets.length == 1 && sockets[0].hasSent('EVENT'),
      );
      publishes.publish(
        event,
        relays: [url],
        auth: AuthPolicy.require(fakeAccount(bob)),
      );
      await eventually(
        () => sockets.length == 2 && sockets[1].hasSent('EVENT'),
      );

      sockets[1].receive(['OK', event.id, false, 'auth-required: who are you']);
      await pumpEventQueue();
      expect(anonymous.outcomes[url], const RelayPublishOutcome.pending());

      sockets[0].receive(['OK', event.id, true, '']);
      expect((await anonymous.done)[url], const RelayPublishOutcome.accepted());
    },
  );
}
