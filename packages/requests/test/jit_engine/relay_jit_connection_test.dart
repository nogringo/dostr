import '../mocks/requests_client.dart';
import 'dart:async';

import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_cache/ndk_cache.dart';

import 'package:test/test.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';

import '../mocks/mock_event_verifier.dart';
import '../mocks/nip65_events.dart';

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
    return Nip01Event(
      kind: Nip01Event.kTextNoteKind,
      pubKey: key2.publicKey,
      content: "some note from key ${keyNames[key2]}",
      tags: [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<KeyPair, Nip01Event> key1TextNotes = {key1: textNote(key1)};
  Map<KeyPair, Nip01Event> key2TextNotes = {key2: textNote(key2)};
  Map<KeyPair, Nip01Event> key3TextNotes = {key3: textNote(key3)};
  Map<KeyPair, Nip01Event> key4TextNotes = {key4: textNote(key4)};

  MockRelay relay21 = MockRelay(name: "relay 21", port: 5021);
  MockRelay relay22 = MockRelay(name: "relay 22", port: 5022);
  MockRelay relay23 = MockRelay(name: "relay 23", port: 5023);
  MockRelay relay24 = MockRelay(name: "relay 24", port: 5024);

  group("Calculate best relays (internal MOCKs)", () {
    Nip65 nip65ForKey1 = Nip65.fromMap(key1.publicKey, {
      relay21.url: ReadWriteMarker.readWrite,
      relay22.url: ReadWriteMarker.readWrite,
      relay23.url: ReadWriteMarker.readWrite,
      relay24.url: ReadWriteMarker.readWrite,
    });
    Nip65 nip65ForKey2 = Nip65.fromMap(key2.publicKey, {
      relay21.url: ReadWriteMarker.readWrite,
      relay22.url: ReadWriteMarker.readWrite,
    });
    Nip65 nip65ForKey3 = Nip65.fromMap(key3.publicKey, {
      relay21.url: ReadWriteMarker.readWrite,
    });
    Nip65 nip65ForKey4 = Nip65.fromMap(key4.publicKey, {
      relay24.url: ReadWriteMarker.readWrite,
    });

    Map<KeyPair, Nip65> nip65s = {
      key1: nip65ForKey1,
      key2: nip65ForKey2,
      key3: nip65ForKey3,
      key4: nip65ForKey4,
    };

    stopServers() async {
      await Future.wait([
        relay21.stop(),
        relay22.stop(),
        relay23.stop(),
        relay24.stop(),
      ]);
    }

    startServers() async {
      addTearDown(stopServers);
      // r1 -> k1, k2, k3
      // r2 -> k1, k2
      // r3 -> k1
      // r4 -> k1,k4
      await Future.wait([
        relay21.start(
          events: [
            ...nip65Events(nip65s),
            ...key1TextNotes.values,
            ...key2TextNotes.values,
            ...key3TextNotes.values,
          ],
        ),
        relay22.start(
          events: [
            ...nip65Events(nip65s),
            ...key1TextNotes.values,
            ...key2TextNotes.values,
          ],
        ),
        relay23.start(
          events: [...nip65Events(nip65s), ...key1TextNotes.values],
        ),
        relay24.start(events: (key4TextNotes..addAll(key1TextNotes)).values),
      ]);
    }

    test('query events from one seed relay', () async {
      await startServers();
      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.jit,
        bootstrapRelays: [relay21.url],
      );
      addTearDown(ndk.destroy);

      // Use the complete request pipeline so events reach the result stream,
      // and wait for completion before shutting down its relay connections.
      final response = ndk.requests.query(
        name: 'debug-get-events',
        filters: [
          Filter(kinds: [Nip01Event.kTextNoteKind], authors: [key3.publicKey]),
        ],
      );
      expect(await response.stream.toList(), contains(key3TextNotes[key3]));
    });

    test(
      'query with inbox/outbox',
      timeout: const Timeout(Duration(seconds: 5)),
      () async {
        await startServers();

        CacheManager cacheManager = MemCacheManager();

        // save nip65 data
        await cacheManager.saveEvents(
          nip65s.values.map((e) => e.toEvent()).toList(),
        );

        await cacheManager.saveUserRelayLists(
          nip65s.values.map((e) => UserRelayList.fromNip65(e)).toList(),
        );

        final ndk = RequestsClient(
          eventVerifier: MockEventVerifier(),
          cache: cacheManager,
          engine: Engine.jit,
          bootstrapRelays: [],
        );

        addTearDown(ndk.destroy);

        final response = ndk.requests.query(
          name: "qInOut",
          filters: [
            Filter(
              kinds: [Nip01Event.kTextNoteKind],
              authors: [
                key1.publicKey,
                key2.publicKey,
                key3.publicKey,
                key4.publicKey,
              ],
            ),
          ],
          desiredCoverage: 1,
        );
        // List<Nip01Event> responses = [];
        // response.stream.listen((event) {
        //   responses.add(event);
        // });

        final responses = await response.stream.toList();

        expect(responses.length, 4);
        // expect that all responses are there
        expect(responses.contains(key1TextNotes[key1]), true);
        expect(responses.contains(key2TextNotes[key2]), true);
        expect(responses.contains(key3TextNotes[key3]), true);
        expect(responses.contains(key4TextNotes[key4]), true);
      },
    );
  });
}
