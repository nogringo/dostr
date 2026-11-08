import 'package:ndk/entities.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/mock_event_verifier.dart';
import '../mocks/nip65_events.dart';

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

  group('high level - network faster then timeout', () {
    KeyPair key1 = Bip340.generatePrivateKey();

    MockRelay relay3 = MockRelay(name: "relay 3", port: 8203);
    MockRelay relay4 = MockRelay(name: "relay 4", port: 8204);

    MockRelay relay5 = MockRelay(name: "relay 3", port: 8205);
    MockRelay relay6 = MockRelay(name: "relay 4", port: 8206);

    Nip65 nip65ForKey1 = Nip65.fromMap(key1.publicKey, {
      relay3.url: ReadWriteMarker.readWrite,
      relay5.url: ReadWriteMarker.readWrite,
      "dead-gossip-relay1.example.com": ReadWriteMarker.readWrite,
      "dead-gossip-relay2.example.com": ReadWriteMarker.readWrite,
    });

    Map<KeyPair, Nip01Event> key1TextNotes = {key1: textNote(key1)};

    Map<KeyPair, Nip65> nip65s = {key1: nip65ForKey1};

    const timoutMiliseconds = 5000;

    // startup and teardown
    setUp(() async {
      await relay3.start(events: key1TextNotes.values);
      await relay4.start(events: nip65Events(nip65s));
      await relay5.start(events: key1TextNotes.values);
      await relay6.start(events: nip65Events(nip65s));
    });

    tearDown(() async {
      await relay3.stop();
      await relay4.stop();
      await relay5.stop();
      await relay6.stop();
    });

    test('query - nip65', () async {
      NdkConfig config = NdkConfig(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: NdkEngine.JIT,
        bootstrapRelays: [relay3.url, relay4.url],
      );

      final ndk = Ndk(config);

      bool timeoutTriggered = false;
      bool timeoutUserTriggered = false;
      // Start the stopwatch
      final stopwatch = Stopwatch()..start();

      final response = ndk.userRelayLists.getSingleUserRelayList(
        key1.publicKey,
      );

      // wait for completion
      await response;

      // Stop the stopwatch
      stopwatch.stop();

      expect(timeoutUserTriggered, isFalse);
      expect(timeoutTriggered, isFalse);

      expect(stopwatch.elapsedMilliseconds, lessThan(timoutMiliseconds));

      print(
        'high level - network faster then timeout Query took: ${stopwatch.elapsedMilliseconds}ms',
      );
    });

    test('query - nip65 - no data', () async {
      NdkConfig config = NdkConfig(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: NdkEngine.JIT,
        bootstrapRelays: [relay3.url, relay4.url],
      );

      final ndk = Ndk(config);

      bool timeoutTriggered = false;
      bool timeoutUserTriggered = false;
      // Start the stopwatch
      final stopwatch = Stopwatch()..start();

      final response = ndk.userRelayLists.getSingleUserRelayList(
        "notExistingPubkey",
      );

      // wait for completion
      await response;

      // Stop the stopwatch
      stopwatch.stop();

      expect(timeoutUserTriggered, isFalse);
      expect(timeoutTriggered, isFalse);

      expect(stopwatch.elapsedMilliseconds, lessThan(timoutMiliseconds));
    });

    test('query - metadata - no data', () async {
      NdkConfig config = NdkConfig(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: NdkEngine.JIT,
        bootstrapRelays: [relay3.url, relay4.url],
      );

      final ndk = Ndk(config);

      bool timeoutTriggered = false;
      bool timeoutUserTriggered = false;
      // Start the stopwatch
      final stopwatch = Stopwatch()..start();

      final response = ndk.metadata.loadMetadata("notExistingPubkey");

      // wait for completion
      await response;

      // Stop the stopwatch
      stopwatch.stop();

      expect(timeoutUserTriggered, isFalse);
      expect(timeoutTriggered, isFalse);

      expect(stopwatch.elapsedMilliseconds, lessThan(timoutMiliseconds));
    });

    test('query - repeated - nip65 data with dead relays', () async {
      NdkConfig config = NdkConfig(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: NdkEngine.JIT,
        bootstrapRelays: [relay6.url],
        logLevel: Logger.logLevels.all,
      );

      final ndk = Ndk(config);
      await ndk.bootstrapRelaysConnected;
      bool timeoutTriggered = false;
      bool timeoutUserTriggered = false;
      // Start the stopwatch
      final stopwatch = Stopwatch()..start();

      final response1 = ndk.userRelayLists.getSingleUserRelayList(
        key1.publicKey,
      );

      // wait for completion
      final response1Data = await response1;

      expect(response1Data, isNotNull);

      final response2 = ndk.requests.query(
        filters: [
          Filter(authors: [key1.publicKey], kinds: [Nip01Event.kTextNoteKind]),
        ],
      );

      final responseData = await response2.future;
      expect(responseData, isNotEmpty);

      // Stop the stopwatch
      stopwatch.stop();

      expect(timeoutUserTriggered, isFalse);
      expect(timeoutTriggered, isFalse);

      expect(stopwatch.elapsedMilliseconds, lessThan(timoutMiliseconds));
    });
  });
}
