import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/requests_client.dart';
import '../mocks/mock_event_verifier.dart';

void main() {
  Nip01Event textNote(KeyPair key, String content) {
    return Nip01Event(
      kind: Nip01Event.kTextNoteKind,
      pubKey: key.publicKey,
      content: content,
      tags: [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  test(
    'same filter on two different relays should not share results',
    () async {
      final key = Bip340.generatePrivateKey();

      final noteOnRelay1 = textNote(key, "note only on relay 1");
      final noteOnRelay2 = textNote(key, "note only on relay 2");

      final relay1 = MockRelay(name: "relay 1");
      final relay2 = MockRelay(name: "relay 2");

      await relay1.start(events: [noteOnRelay1]);
      await relay2.start(events: [noteOnRelay2]);
      addTearDown(relay1.stop);
      addTearDown(relay2.stop);

      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [relay1.url, relay2.url],
      );
      addTearDown(ndk.destroy);

      await _waitForRelayConnected(ndk: ndk, relayUrl: relay1.url);
      await _waitForRelayConnected(ndk: ndk, relayUrl: relay2.url);

      final filter = Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key.publicKey],
      );

      final results = await Future.wait([
        ndk.requests.query(filter: filter, explicitRelays: [relay1.url]).future,
        ndk.requests.query(filter: filter, explicitRelays: [relay2.url]).future,
      ]);

      expect(
        results[0].map((e) => e.id),
        orderedEquals([noteOnRelay1.id]),
        reason: 'query on relay 1 should return the event stored on relay 1',
      );
      expect(
        results[1].map((e) => e.id),
        unorderedEquals([noteOnRelay2.id]),
        reason: 'query on relay 2 should return the event stored on relay 2',
      );
    },
  );
}

Future<void> _waitForRelayConnected({
  required RequestsClient ndk,
  required String relayUrl,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final current = ndk.relays.getRelayConnectivity(relayUrl);
  if (current?.isConnected == true) {
    return;
  }

  await ndk.relays.relayConnectivityChanges
      .firstWhere(
        (connections) => connections.any(
          (connection) => connection.url == relayUrl && connection.isConnected,
        ),
      )
      .timeout(timeout);
}
