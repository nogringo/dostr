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
