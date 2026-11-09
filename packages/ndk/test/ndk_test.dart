import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import 'mocks/mock_event_verifier.dart';

void main() async {
  KeyPair key1 = Bip340.generatePrivateKey();
  KeyPair key2 = Bip340.generatePrivateKey();
  KeyPair key3 = Bip340.generatePrivateKey();
  KeyPair key4 = Bip340.generatePrivateKey();

  Map<KeyPair, String> keyNames = {
    key1: "key1",
    key2: "key2",
    key3: "key3",
    key4: "key4",
  };

  Nip01Event textNote(KeyPair key2) {
    Nip01Event event = Nip01Event(
      kind: Nip01Event.kTextNoteKind,
      pubKey: key2.publicKey,
      content: "some note from key ${keyNames[key2]}",
      tags: [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final signedEvent = Bip340.signEvent(
      event: event,
      privateKey: key2.privateKey!,
    );

    return signedEvent;
  }

  Map<KeyPair, Nip01Event> key1TextNotes = {key1: textNote(key1)};

  group('Ndk', () {
    test('opens no connection to its bootstrap relays when built', () async {
      final relay = MockRelay(name: "bootstrap");
      await relay.start();
      final ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relay.url],
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(relay.clients, isEmpty);
      expect(ndk.relays.connectivities, isEmpty);

      await ndk.destroy();
      await relay.stop();
    });

    test(
      'query simple note LISTS',
      timeout: const Timeout(Duration(seconds: 3)),
      () async {
        MockRelay relay1 = MockRelay(name: "relay 1", port: 3960);
        await relay1.start(events: key1TextNotes.values);

        final ndk = Ndk(
          NdkConfig(
            eventVerifier: Bip340EventVerifier(),
            cache: MemCacheManager(),
            engine: NdkEngine.RELAY_SETS,
            bootstrapRelays: [relay1.url],
          ),
        );
        ndk.accounts.loginPrivateKey(
          pubkey: key1.publicKey,
          privkey: key1.privateKey!,
        );

        final response = ndk.requests.query(
          filters: [
            Filter(
              kinds: [Nip01Event.kTextNoteKind],
              authors: [key1.publicKey],
            ),
          ],
        );

        await expectLater(
          response.stream,
          emitsInAnyOrder(key1TextNotes.values),
        );

        final response2 = ndk.requests.query(
          filters: [
            Filter(
              kinds: [Nip01Event.kTextNoteKind],
              authors: [key1.publicKey, key2.publicKey],
            ),
          ],
        );

        await expectLater(
          response2.stream,
          emitsInAnyOrder(key1TextNotes.values),
        );

        await relay1.stop();
      },
    );

    test(
      'query simple event by id',
      timeout: const Timeout(Duration(seconds: 3)),
      () async {
        MockRelay relay1 = MockRelay(name: "relay 1", port: 3961);
        await relay1.start(events: key1TextNotes.values);

        final cache = MemCacheManager();

        final ndk = Ndk(
          NdkConfig(
            eventVerifier: Bip340EventVerifier(),
            cache: cache,
            engine: NdkEngine.RELAY_SETS,
            bootstrapRelays: [relay1.url],
          ),
        );
        final response = ndk.requests.query(
          filters: [
            Filter(ids: [key1TextNotes[key1]!.id]),
          ],
        );

        await expectLater(
          response.stream,
          emitsInAnyOrder(key1TextNotes.values),
        );

        await cache.saveEvent(key1TextNotes[key1]!);

        final response2 = ndk.requests.query(
          filters: [
            Filter(ids: [key1TextNotes[key1]!.id]),
          ],
        );

        await expectLater(
          response2.stream,
          emitsInAnyOrder(key1TextNotes.values),
        );

        await relay1.stop();
      },
    );
    // ================================================================================================

    test('verify signatures of events', () async {
      MockRelay relay1 = MockRelay(name: "relay 1", port: 3962);
      await relay1.start(events: key1TextNotes.values);

      final ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(result: false),
          cache: MemCacheManager(),
          engine: NdkEngine.RELAY_SETS,
          bootstrapRelays: [relay1.url],
        ),
      );

      final response = ndk.requests.query(
        filters: [
          Filter(authors: [key1.publicKey], kinds: [Nip01Event.kTextNoteKind]),
        ],
      );
      await for (final _ in response.stream) {
        fail("should not emit any events, since relay does not sign");
      }
      await relay1.stop();
    });

    test(
      'emptyBootstrapRelaysConfig with non-list welcome message from explicit relay',
      () async {
        final welcomeMessage =
            '{"welcome": {"motd": "test message"}, "type": "welcome"}';
        MockRelay explicitRelay = MockRelay(name: "explicitRelay", port: 3963)
          ..onConnect = (client) => client.sendRaw(welcomeMessage);
        await explicitRelay.start();

        final ndk = Ndk.emptyBootstrapRelaysConfig();

        final query = ndk.requests.query(
          filters: [
            Filter(kinds: [0]),
          ],
          explicitRelays: [explicitRelay.url],
        );

        await query.future;

        ndk.destroy();
        await explicitRelay.stop();
      },
    );

    test(
      'should handle null values in events from relays gracefully',
      () async {
        MockRelay explicitRelay = MockRelay(name: "malformedRelay", port: 3966)
          ..onMessage = (client, message) {
            if (message[0] != 'REQ') return false;
            client.send([
              'EVENT',
              message[1],
              {
                'id': null,
                'pubkey': null,
                'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                'kind': 0,
                'tags': [],
                'content': null,
                'sig': null,
              },
            ]);
            client.send(['EOSE', message[1]]);
            return true;
          };
        await explicitRelay.start(events: key1TextNotes.values);

        final ndk = Ndk.emptyBootstrapRelaysConfig();

        final query = ndk.requests.query(
          filters: [
            Filter(kinds: [0]),
          ],
          explicitRelays: [explicitRelay.url],
        );

        await query.future;

        ndk.destroy();
        await explicitRelay.stop();
      },
    );
  });
}
