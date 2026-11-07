import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';

import '../mocks/mock_event_verifier.dart';

void main() {
  final author = Bip340.generatePrivateKey();
  final mentioned = Bip340.generatePrivateKey();

  Nip01Event signedNote({List<List<String>> tags = const []}) =>
      Bip340.signEvent(
        event: Nip01Event(
          pubKey: author.publicKey,
          kind: Nip01Event.kTextNoteKind,
          tags: tags,
          content: 'a note',
        ),
        privateKey: author.privateKey!,
      );

  int received(MockRelay relay, Nip01Event event) =>
      relay.receivedEvents.where((e) => e.id == event.id).length;

  group('RelayPublishes', () {
    late MockRelay relayA;
    late MockRelay relayB;
    late Ndk ndk;

    setUp(() {
      relayA = MockRelay(name: 'relay a');
      relayB = MockRelay(name: 'relay b');
      ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [],
        ),
      );
    });

    tearDown(() async {
      await ndk.destroy();
      await relayA.stop();
      await relayB.stop();
    });

    test('collects the OK of every relay, each sent the event once', () async {
      await relayA.start();
      await relayB.start();
      final note = signedNote();

      final responses = await ndk.relayPublishes
          .publish(note, relays: [relayA.url, relayB.url, relayA.url])
          .done;

      expect(responses.keys, unorderedEquals([relayA.url, relayB.url]));
      expect(responses.values.every((r) => r.broadcastSuccessful), isTrue);
      expect(received(relayA, note), 1);
      expect(received(relayB, note), 1);
      expect(await ndk.config.cache.loadEvent(note.id), isNull);
    });

    test('a relay nothing listens on is reported as failed', () async {
      final responses = await ndk.relayPublishes
          .publish(signedNote(), relays: [relayA.url])
          .done;

      expect(responses[relayA.url]!.broadcastSuccessful, isFalse);
      expect(
        responses[relayA.url]!.failure?.kind,
        RelayFailureKind.unreachable,
      );
    });

    test('no relay at all is done right away', () async {
      final responses = await ndk.relayPublishes
          .publish(signedNote(), relays: const [])
          .done;

      expect(responses, isEmpty);
    });

    test('an unsigned event is refused', () {
      final unsigned = Nip01Event(
        pubKey: author.publicKey,
        kind: Nip01Event.kTextNoteKind,
        tags: const [],
        content: 'not signed',
      );

      expect(
        () => ndk.relayPublishes.publish(unsigned, relays: [relayA.url]),
        throwsArgumentError,
      );
    });
  });

  for (final engine in [NdkEngine.RELAY_SETS, NdkEngine.JIT]) {
    test('[${engine.name}] a relay both in the outbox and an inbox gets the '
        'event once', () async {
      final relay = MockRelay(name: 'outbox and inbox');
      await relay.start();
      addTearDown(relay.stop);

      // the relay lists with the events they come from: saving the note
      // rebuilds the author's list from the cached kind 10002 events
      final cache = MemCacheManager();
      final nip65s = [
        for (final key in [author, mentioned])
          Nip65.fromMap(key.publicKey, {relay.url: ReadWriteMarker.readWrite}),
      ];
      await cache.saveEvents([for (final nip65 in nip65s) nip65.toEvent()]);
      await cache.saveUserRelayLists(
        nip65s.map(UserRelayList.fromNip65).toList(),
      );
      final ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: cache,
          engine: engine,
          bootstrapRelays: [],
        ),
      );
      addTearDown(ndk.destroy);

      final note = signedNote(
        tags: [
          ['p', mentioned.publicKey],
        ],
      );
      final responses = await ndk.broadcast
          .broadcast(nostrEvent: note)
          .broadcastDoneFuture;

      expect(responses.map((r) => r.relayUrl), [relay.url]);
      // the first OK ends the broadcast, a second EVENT would come after it
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(received(relay, note), 1);
    });
  }
}
