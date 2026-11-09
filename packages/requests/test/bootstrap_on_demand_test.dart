import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import 'mocks/mock_event_verifier.dart';
import 'mocks/requests_client.dart';

void main() {
  final key = Bip340.generatePrivateKey();
  final note = Nip01Event(
    kind: Nip01Event.kTextNoteKind,
    pubKey: key.publicKey,
    content: 'note on a bootstrap relay',
    tags: [],
  );

  for (final engine in Engine.values) {
    group('${engine.name} opens the bootstrap relays it sends to', () {
      late MockRelay relay;
      late RequestsClient client;

      setUp(() async {
        relay = MockRelay(name: 'bootstrap');
        await relay.start(events: [note]);
        client = RequestsClient(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          engine: engine,
          bootstrapRelays: [relay.url],
        );
      });

      tearDown(() async {
        await client.destroy();
        await relay.stop();
      });

      test('nothing connects to them before a request', () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(relay.clients, isEmpty);
        expect(client.relays.connectivities, isEmpty);
      });

      test('a filter without authors', () async {
        final events = await client.requests
            .query(filter: Filter(kinds: [Nip01Event.kTextNoteKind]))
            .future;
        expect(events.map((event) => event.id), [note.id]);
      });

      test('authors without a known relay list', () async {
        final events = await client.requests
            .query(
              filter: Filter(
                kinds: [Nip01Event.kTextNoteKind],
                authors: [key.publicKey],
              ),
            )
            .future;
        expect(events.map((event) => event.id), [note.id]);
      });
    });
  }
}
