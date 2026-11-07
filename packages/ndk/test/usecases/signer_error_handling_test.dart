import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/mock_event_verifier.dart';
import '../mocks/mock_failing_signer.dart';

/// Tests for issue #450: Missing error handling for EventSigner methods
/// https://github.com/relaystr/ndk/issues/450
void main() {
  group('signer error handling', () {
    final key0 = Bip340.generatePrivateKey();
    late MockRelay relay0;
    late Ndk ndk;
    late MockFailingSigner failingSigner;

    setUp(() async {
      relay0 = MockRelay(name: "relay 0", port: 5110);
      await relay0.start();

      ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relay0.url],
        ),
      );

      failingSigner = MockFailingSigner(publicKey: key0.publicKey);
      ndk.accounts.loginExternalSigner(signer: failingSigner);
    });

    tearDown(() async {
      await failingSigner.dispose();
      await ndk.destroy();
      await relay0.stop();
    });

    test('broadcast should throw SignerRequestRejectedException', () async {
      final event = Nip01Event(
        pubKey: key0.publicKey,
        kind: Nip01Event.kTextNoteKind,
        tags: [],
        content: "test",
      );

      await expectLater(
        ndk.broadcast
            .broadcast(nostrEvent: event, specificRelays: [relay0.url])
            .broadcastDoneFuture,
        throwsA(isA<SignerRequestRejectedException>()),
      );
    });
  });
}
