import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/requests_client.dart';
import '../mocks/mock_event_verifier.dart';

void main() {
  Nip01Event textNote(KeyPair key2) {
    return Nip01Event(
      kind: Nip01Event.kTextNoteKind,
      pubKey: key2.publicKey,
      content: "some note from key $key2}",
      tags: [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  group('Timeout - query', () {
    KeyPair key1 = Bip340.generatePrivateKey();
    late MockRelay relay1;
    late MockRelay silentRelay;
    late RequestsClient ndk;
    Map<KeyPair, Nip01Event> key1TextNotes = {key1: textNote(key1)};

    // startup and teardown
    setUp(() async {
      relay1 = MockRelay(name: "relay 1");
      await relay1.start();
      relay1.events.addAll(key1TextNotes.values);

      silentRelay = MockRelay(name: "silent relay", answerRequests: false);
      await silentRelay.start();
    });

    tearDown(() async {
      await ndk.destroy();
      await relay1.stop();
      await silentRelay.stop();
    });

    test('timeout does not trigger on normal request', () async {
      ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.relaySets,
        bootstrapRelays: [relay1.url],
      );

      bool timeoutTriggered = false;
      bool timeoutUserTriggered = false;

      final response = ndk.requests.query(
        filters: [
          Filter(authors: [key1.publicKey]),
        ],
        // Allow enough headroom to remain stable under parallel suite load.
        timeout: Duration(seconds: 4),
        timeoutCallback: () {
          timeoutTriggered = true;
        },
        timeoutCallbackUserFacing: () {
          timeoutUserTriggered = true;
        },
      );

      // wait for completion
      await response.future;

      expect(timeoutUserTriggered, isFalse);
      expect(timeoutTriggered, isFalse);
    });

    test('timeout triggers', () async {
      ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.relaySets,
        bootstrapRelays: [silentRelay.url],
      );

      bool timeoutTriggered = false;
      bool timeoutUserTriggered = false;

      final response = ndk.requests.query(
        filters: [
          Filter(authors: ["unknown"]),
        ],
        // short to fail fast
        timeout: Duration(seconds: 1),
        timeoutCallback: () {
          timeoutTriggered = true;
        },
        timeoutCallbackUserFacing: () {
          timeoutUserTriggered = true;
        },
      );

      // wait for completion
      await response.future;

      expect(timeoutUserTriggered, isTrue);
      expect(timeoutTriggered, isTrue);
    });

    test(
      'timeout triggers default ndk values within expected time window',
      () async {
        const Duration myTimeout = Duration(seconds: 1);
        ndk = RequestsClient(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          engine: Engine.relaySets,
          bootstrapRelays: [silentRelay.url],
          defaultQueryTimeout: myTimeout,
        );

        bool timeoutTriggered = false;
        bool timeoutUserTriggered = false;

        // Start the stopwatch
        final stopwatch = Stopwatch()..start();

        final response = ndk.requests.query(
          filters: [
            Filter(authors: ["unknown"]),
          ],
          // short to fail fast
          timeoutCallback: () {
            timeoutTriggered = true;
          },
          timeoutCallbackUserFacing: () {
            timeoutUserTriggered = true;
          },
        );

        // Wait for completion
        await response.future;

        // Stop the stopwatch
        stopwatch.stop();

        // Get the elapsed time
        final elapsedMilliseconds = stopwatch.elapsedMilliseconds;

        // Assert that timeout callbacks were triggered
        expect(timeoutUserTriggered, isTrue);
        expect(timeoutTriggered, isTrue);

        // Assert that the timeout occurred within the expected time window
        // Adjust these values based on your expected timeout duration
        expect(
          elapsedMilliseconds,
          greaterThanOrEqualTo(myTimeout.inMilliseconds - 1000),
        ); // lower bound
        expect(
          elapsedMilliseconds,
          lessThanOrEqualTo(myTimeout.inMilliseconds + 1000),
        ); // upper bound
      },
    );
  });
}
