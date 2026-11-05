import 'dart:async';

import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import '../../../cashu/test/mocks/mock_event_verifier.dart';
import '../mocks/mock_relay.dart';

Future<void> _waitUntil(
  bool Function() condition, {
  String reason = 'condition never became true',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(reason);
}

void main() {
  final key = Bip340.generatePrivateKey();
  final filter = Filter(
    kinds: [Nip01Event.kTextNodeKind],
    authors: [key.publicKey],
  );

  Nip01Event textNote() => Bip340.signEvent(
    event: Nip01Event(
      kind: Nip01Event.kTextNodeKind,
      pubKey: key.publicKey,
      content: 'a note',
      tags: [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
    privateKey: key.privateKey!,
  );

  Ndk buildNdk({bool validSignatures = true}) => Ndk(
    NdkConfig(
      cache: MemCacheManager(),
      eventVerifier: MockEventVerifier(result: validSignatures),
      bootstrapRelays: [],
    ),
  );

  group('RelayReq', () {
    late MockRelay relayA;
    late MockRelay relayB;
    late Ndk ndk;

    setUp(() {
      relayA = MockRelay(name: 'relay a', signEvents: false);
      relayB = MockRelay(name: 'relay b', signEvents: false);
      ndk = buildNdk();
    });

    tearDown(() async {
      await ndk.destroy();
      await relayA.stopServer();
      await relayB.stopServer();
    });

    test('a query ends on EOSE, with one copy per relay', () async {
      final note = textNote();
      await relayA.startServer(textNotes: {key: note});
      await relayB.startServer(textNotes: {key: note});

      final req = ndk.relayReqs.req(
        relays: {
          relayA.url: [filter],
          relayB.url: [filter],
        },
      );
      final events = await req.events.toList();

      expect(events.map((e) => e.event.id), [note.id, note.id]);
      expect(
        events.map((e) => e.relayUrl),
        unorderedEquals([relayA.url, relayB.url]),
      );
      expect(await req.done, {
        relayA.url: RelayRequestOutcome(RelayRequestStatus.eose),
        relayB.url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });

    test('a request does not end before it is sealed', () async {
      await relayA.startServer();
      final req = ndk.relayReqs.req();
      var ended = false;
      unawaited(req.done.then((_) => ended = true));

      req.send(relayA.url, [filter]);
      await _waitUntil(
        () => req.outcomes[relayA.url]?.status == RelayRequestStatus.eose,
        reason: 'the relay never answered',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(ended, isFalse);

      req.seal();
      expect(await req.done, {
        relayA.url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });

    test('a request sealed without relays ends right away', () async {
      final req = ndk.relayReqs.req(relays: {});

      expect(await req.done, isEmpty);
      expect(await req.events.toList(), isEmpty);
    });

    test('a subscription outlives EOSE and sends CLOSE once closed', () async {
      await relayA.startServer();
      final req = ndk.relayReqs.req(
        relays: {
          relayA.url: [filter],
        },
        closeOnEose: false,
      );
      final received = Completer<Nip01Event>();
      req.events.listen((e) {
        if (!received.isCompleted) received.complete(e.event);
      });
      await _waitUntil(
        () => relayA.activeSubscriptionCount == 1,
        reason: 'the relay never got the subscription',
      );

      final live = textNote();
      relayA.sendEvent(event: live, subId: req.id);
      expect((await received.future).id, live.id);

      await req.close();
      await _waitUntil(
        () => relayA.activeSubscriptionCount == 0,
        reason: 'the relay never got the CLOSE',
      );
      await req.done;
    });

    test('cancelling the events subscription closes the request', () async {
      await relayA.startServer();
      final req = ndk.relayReqs.req(
        relays: {
          relayA.url: [filter],
        },
        closeOnEose: false,
      );
      final subscription = req.events.listen((_) {});
      await _waitUntil(
        () => relayA.activeSubscriptionCount == 1,
        reason: 'the relay never got the subscription',
      );

      await subscription.cancel();

      await _waitUntil(
        () => relayA.activeSubscriptionCount == 0,
        reason: 'the relay never got the CLOSE',
      );
      await req.done;
    });

    test('a relay nothing listens on is reported notSent', () async {
      final req = ndk.relayReqs.req(
        relays: {
          relayA.url: [filter],
        },
      );

      expect(await req.done, {
        relayA.url: RelayRequestOutcome(
          RelayRequestStatus.notSent,
          message: 'could not connect',
        ),
      });
    });

    test('a timeout ends a query its relay never answers', () async {
      final silent = MockRelay(
        name: 'silent',
        signEvents: false,
        silenceRequests: true,
      );
      await silent.startServer();
      addTearDown(silent.stopServer);

      final req = ndk.relayReqs.req(
        relays: {
          silent.url: [filter],
        },
        timeout: const Duration(milliseconds: 500),
      );

      expect(await req.done, {
        silent.url: RelayRequestOutcome(RelayRequestStatus.timedOut),
      });
    });

    test('a relay takes one send, and one sent after seal counts', () async {
      await relayA.startServer();
      await relayB.startServer();
      final req = ndk.relayReqs.req();

      expect(req.send(relayA.url, [filter]), isTrue);
      expect(req.send(relayA.url, [filter]), isFalse);
      req.seal();
      expect(req.send(relayB.url, [filter]), isTrue);

      expect(await req.done, {
        relayA.url: RelayRequestOutcome(RelayRequestStatus.eose),
        relayB.url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });

    test('nothing is sent once the request is over', () async {
      final req = ndk.relayReqs.req(relays: {});
      await req.done;

      expect(req.send(relayA.url, [filter]), isFalse);
      expect(req.outcomes, isEmpty);
    });

    test('an id already in flight is refused', () async {
      final req = ndk.relayReqs.req(id: 'taken');

      expect(() => ndk.relayReqs.req(id: 'taken'), throwsStateError);

      await req.close();
    });

    test('events that fail verification are dropped', () async {
      await relayA.startServer(textNotes: {key: textNote()});
      final rejecting = buildNdk(validSignatures: false);
      addTearDown(rejecting.destroy);

      final req = rejecting.relayReqs.req(
        relays: {
          relayA.url: [filter],
        },
      );

      expect(await req.events.toList(), isEmpty);
      expect(await req.done, {
        relayA.url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });
  });
}
