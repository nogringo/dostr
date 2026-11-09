import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import 'mocks/requests_client.dart';
import 'mocks/mock_event_verifier.dart';

void main() {
  test(
    'duplicate request should not wait for timeout when original completes',
    () async {
      final key = Bip340.generatePrivateKey();

      // Create a mock relay that responds quickly
      final relay = MockRelay(name: "relay duplicate test", port: 5105);

      await relay.start();

      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [relay.url],
        defaultQueryTimeout: const Duration(seconds: 5),
      );

      final stopwatch = Stopwatch()..start();
      final filter = Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key.publicKey],
      );

      // Create two identical requests at the same time (same filter)
      // One will be treated as a duplicate
      final futures = await Future.wait([
        ndk.requests.query(filter: filter, explicitRelays: [relay.url]).future,
        ndk.requests.query(filter: filter, explicitRelays: [relay.url]).future,
      ]);

      stopwatch.stop();

      // Both requests should complete quickly (when relay responds with EOSE)
      // NOT wait for the 5s query timeout
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason:
            'Both requests should complete quickly when relay responds. '
            'Elapsed: ${stopwatch.elapsedMilliseconds}ms. '
            'If this fails, the duplicate request timeout fix is needed.',
      );

      expect(futures[0], isEmpty);
      expect(futures[1], isEmpty);

      await ndk.destroy();
      await relay.stop();
    },
  );
}
