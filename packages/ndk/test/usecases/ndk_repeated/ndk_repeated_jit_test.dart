// ignore_for_file: file_names

import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../../mocks/mock_event_verifier.dart';
import 'test_repeated.dart';

void main() async {
  group('repeated queries', () {
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

    MockRelay relay1 = MockRelay(name: "relay 1", port: 4140);
    MockRelay relay2 = MockRelay(name: "relay 2", port: 4141);
    MockRelay relay3 = MockRelay(name: "relay 3", port: 4142);
    MockRelay relay4 = MockRelay(name: "relay 4", port: 4143);

    final myRelayUrls = [relay1.url, relay2.url, relay3.url, relay4.url];

    final myFilters = [
      Filter(kinds: [Nip01Event.kTextNoteKind], authors: [key1.publicKey]),
      Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key1.publicKey, key2.publicKey],
      ),
      Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key4.publicKey, key3.publicKey],
      ),
      Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key4.publicKey, key2.publicKey],
      ),
      Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [key1.publicKey, key2.publicKey, key3.publicKey],
      ),
      Filter(
        kinds: [Nip01Event.kTextNoteKind],
        authors: [
          key1.publicKey,
          key2.publicKey,
          key3.publicKey,
          key4.publicKey,
        ],
      ),
    ];

    setUp(() async {
      await relay1.start(events: key1TextNotes.values);
      await relay2.start(events: key2TextNotes.values);
      await relay3.start(events: key3TextNotes.values);
      await relay4.start(events: key4TextNotes.values);
    });

    tearDown(() async {
      await relay1.stop();
      await relay2.stop();
      await relay3.stop();
      await relay4.stop();
    });

    test('JIT Engine', timeout: const Timeout(Duration(seconds: 3)), () async {
      final ndkJit = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          engine: NdkEngine.JIT,
          bootstrapRelays: myRelayUrls,
        ),
      );
      ndkJit.accounts.loginPrivateKey(
        pubkey: key1.publicKey,
        privkey: key1.privateKey!,
      );

      await testNdk(
        myNdk: ndkJit,
        coverage: 1,
        myFilters: myFilters,
        key1TextNotes: key1TextNotes,
        key2TextNotes: key2TextNotes,
        key3TextNotes: key3TextNotes,
        key4TextNotes: key4TextNotes,
      );
    });
  });
}
