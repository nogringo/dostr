import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/requests_client.dart';
import '../mocks/mock_event_verifier.dart';

/// test to check if the network is faster then the timeout (this should always be the case)
void main() {
  Nip01Event textNote(KeyPair myKey) {
    return Nip01Event(
      kind: Nip01Event.kTextNoteKind,
      pubKey: myKey.publicKey,
      content: "some note from key $myKey}",
      tags: [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  group('low level - network faster then timeout', () {
    KeyPair key1 = Bip340.generatePrivateKey();
    MockRelay relay1 = MockRelay(name: "relay 1", port: 8221);
    MockRelay relay2 = MockRelay(name: "relay 2", port: 8222);

    Map<KeyPair, Nip01Event> key1TextNotes = {key1: textNote(key1)};

    const timoutMiliseconds = 10000;

    // startup and teardown
    setUp(() async {
      await relay1.start(events: key1TextNotes.values);
      await relay2.start();
    });

    tearDown(() async {
      await relay1.stop();
      await relay2.stop();
    });

    test('query', () async {
      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.jit,
        bootstrapRelays: [relay1.url, relay2.url],
        logLevel: Logger.logLevels.error,
      );

      bool timeoutTriggered = false;
      bool timeoutUserTriggered = false;
      // Start the stopwatch
      final stopwatch = Stopwatch()..start();

      final response = ndk.requests.query(
        filters: [
          Filter(authors: [key1.publicKey], kinds: [Nip01Event.kTextNoteKind]),
        ],
        timeout: Duration(milliseconds: timoutMiliseconds),
        timeoutCallback: () {
          timeoutTriggered = true;
        },
        timeoutCallbackUserFacing: () {
          timeoutUserTriggered = true;
        },
      );

      // wait for completion
      final responseData = await response.future;

      // Stop the stopwatch
      stopwatch.stop();

      expect(responseData, isNotEmpty);

      expect(timeoutUserTriggered, isFalse);
      expect(timeoutTriggered, isFalse);

      expect(stopwatch.elapsedMilliseconds, lessThan(timoutMiliseconds));

      print(
        'low level - network faster then timeout Query took: ${stopwatch.elapsedMilliseconds}ms',
      );
    });

    test('query - one dead seed relay', () async {
      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.jit,
        bootstrapRelays: [
          relay1.url,
          relay2.url,
          'wss://dead-relay.example.com',
        ],
        logLevel: Logger.logLevels.all,
      );

      bool timeoutTriggered = false;
      bool timeoutUserTriggered = false;
      // Start the stopwatch
      final stopwatch = Stopwatch()..start();

      final response = ndk.requests.query(
        filters: [
          Filter(authors: [key1.publicKey], kinds: [Nip01Event.kTextNoteKind]),
        ],
        timeout: Duration(milliseconds: timoutMiliseconds),
        timeoutCallback: () {
          timeoutTriggered = true;
        },
        timeoutCallbackUserFacing: () {
          timeoutUserTriggered = true;
        },
      );

      // wait for completion
      final responseData = await response.future;

      // Stop the stopwatch
      stopwatch.stop();

      expect(responseData, isNotEmpty);

      expect(timeoutUserTriggered, isFalse);
      expect(timeoutTriggered, isFalse);

      expect(stopwatch.elapsedMilliseconds, lessThan(timoutMiliseconds));

      print('low level - dead relay took: ${stopwatch.elapsedMilliseconds}ms');
    });
  });

  test('request fails fast when relay is offline', () async {
    final ndk = RequestsClient(
      eventVerifier: MockEventVerifier(),
      cache: MemCacheManager(),
      bootstrapRelays: [],
      defaultQueryTimeout: Duration(hours: 1),
    );

    final events = await ndk.requests
        .query(
          filter: Filter(kinds: [1]),
          explicitRelays: ['ws://127.0.0.1:59999'],
        )
        .future;

    expect(events, isEmpty);
  });
}
