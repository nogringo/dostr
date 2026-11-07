import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/mock_event_verifier.dart';

/// NIP-01: an empty list matches nothing, it does not stand for an absent one.
void main() {
  late MockRelay relay;
  late Ndk ndk;

  final nobody = Filter(kinds: [Nip01Event.kTextNoteKind], authors: []);

  setUp(() async {
    final key = Bip340.generatePrivateKey();
    final note = Bip340.signEvent(
      event: Nip01Event(
        pubKey: key.publicKey,
        kind: Nip01Event.kTextNoteKind,
        tags: [],
        content: 'a note from somebody',
      ),
      privateKey: key.privateKey!,
    );
    relay = MockRelay(name: 'empty list relay');
    await relay.start(events: [note]);
    ndk = Ndk(
      NdkConfig(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [],
      ),
    );
    await ndk.config.cache.saveEvent(note);
  });

  tearDown(() async {
    await ndk.destroy();
    await relay.stop();
  });

  test(
    'a query nothing can match asks neither the cache nor the relays',
    () async {
      final response = ndk.requests.query(
        filter: nobody,
        explicitRelays: [relay.url],
      );

      expect(await response.future, isEmpty);
      expect(await response.relayOutcomesDone, isEmpty);
      expect(relay.totalRequestedSubscriptionCount, 0);
    },
  );

  test('so does a paginated one', () async {
    final response = ndk.requests.query(
      filter: nobody,
      explicitRelays: [relay.url],
      paginate: true,
    );

    expect(await response.future, isEmpty);
    expect(relay.totalRequestedSubscriptionCount, 0);
  });

  test('a subscription nothing can match ends at once', () async {
    final response = ndk.requests.subscription(
      filter: nobody,
      explicitRelays: [relay.url],
    );

    expect(await response.future, isEmpty);
    expect(relay.totalRequestedSubscriptionCount, 0);
  });
}
