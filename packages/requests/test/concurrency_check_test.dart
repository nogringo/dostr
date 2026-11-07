import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import 'mocks/requests_client.dart';
import 'mocks/mock_event_verifier.dart';

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

    MockRelay relay1 = MockRelay(name: "relay 1");
    MockRelay relay2 = MockRelay(name: "relay 2");
    MockRelay relay3 = MockRelay(name: "relay 3");
    MockRelay relay4 = MockRelay(name: "relay 4");

    final myRelayUrls = [relay1.url, relay2.url, relay3.url, relay4.url];

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

    test(
      'test if events get replayed on concurrency requests',
      timeout: const Timeout(Duration(seconds: 10)),
      () async {
        final ndkJit = RequestsClient(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          engine: Engine.jit,
          bootstrapRelays: myRelayUrls,
        );
        ndkJit.accounts.loginPrivateKey(
          pubkey: key1.publicKey,
          privkey: key1.privateKey!,
        );
        await ndkJit.bootstrapRelaysConnected;

        final myfilter = Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        );

        final response0 = ndkJit.requests.query(
          filters: [myfilter],
          desiredCoverage: 1,
        );
        await Future.delayed(Duration(milliseconds: 1));
        final response1 = ndkJit.requests.query(
          filters: [myfilter],
          desiredCoverage: 1,
        );

        final result0 = await response0.future;
        final result1 = await response1.future;

        expect(result0, hasLength(1));
        expect(result0.map((event) => event.id), [key1TextNotes[key1]!.id]);
        expect(result1.map((event) => event.id), [key1TextNotes[key1]!.id]);
        await ndkJit.destroy();
      },
    );
  });

  group('repeated queries under different identities', () {
    final key = Bip340.generatePrivateKey();

    final note = Nip01Event(
      kind: Nip01Event.kTextNoteKind,
      pubKey: key.publicKey,
      content: "a note only an authenticated request may see",
      tags: [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    late MockRelay relay;

    setUp(() async {
      relay = MockRelay(name: "relay", requireAuthForRequests: true);
      await relay.start(events: [note]);
    });

    tearDown(() async {
      await relay.stop();
    });

    test(
      'a request that never authenticates is not served by an authenticated one',
      timeout: const Timeout(Duration(seconds: 10)),
      () async {
        final ndk = RequestsClient(
          authHandler: (_, _) async => true,
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relay.url],
        );
        ndk.accounts.loginPrivateKey(
          pubkey: key.publicKey,
          privkey: key.privateKey!,
        );
        await ndk.bootstrapRelaysConnected;

        final filter = Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key.publicKey],
        );

        // nothing is written to the cache, so only the concurrency check could
        // bridge the two requests
        final authenticated = ndk.requests.query(
          filter: filter,
          cacheWrite: false,
          desiredCoverage: 1,
        );
        await Future.delayed(Duration(milliseconds: 1));
        final anonymous = ndk.requests.query(
          filter: filter,
          auth: const AuthPolicy.never(),
          cacheWrite: false,
          desiredCoverage: 1,
        );

        expect(await authenticated.future, hasLength(1));
        expect(await anonymous.future, isEmpty);

        await ndk.destroy();
      },
    );
  });
}
