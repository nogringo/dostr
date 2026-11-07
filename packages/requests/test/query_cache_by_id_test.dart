import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import 'mocks/requests_client.dart';
import 'mocks/mock_event_verifier.dart';

void main() {
  test(
    'save signed event in cache then query it back with an ids-only filter',
    () async {
      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [],
      );

      final KeyPair keyPair = Bip340.generatePrivateKey();

      final signedEvent = Bip340.signEvent(
        event: Nip01Event(
          pubKey: keyPair.publicKey,
          kind: Nip01Event.kTextNoteKind,
          tags: [],
          content: "hello from cache",
        ),
        privateKey: keyPair.privateKey!,
      );

      await ndk.cache.saveEvent(signedEvent);

      final stopwatch = Stopwatch()..start();
      final events = await ndk.requests
          .query(filter: Filter(ids: [signedEvent.id]))
          .future;
      stopwatch.stop();

      expect(events.length, equals(1));
      expect(events.first.id, equals(signedEvent.id));
      expect(events.first.sig, equals(signedEvent.sig));
      expect(events.first.content, equals("hello from cache"));

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason:
            'an ids-only query fully served by cache should return '
            'immediately, not wait for the query timeout',
      );

      await ndk.destroy();
    },
  );
}
