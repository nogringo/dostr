import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/mock_event_verifier.dart';
import '../mocks/mock_slow_signer.dart';

void main() {
  test(
    'broadcast with slow signer should not timeout during signing',
    timeout: Timeout(Duration(seconds: 60)),
    () async {
      final key = Bip340.generatePrivateKey();
      final relay = MockRelay(name: "relay");
      await relay.start();

      final ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relay.url],
        ),
      );
      await ndk.bootstrapRelaysConnected;

      ndk.accounts.loginExternalSigner(
        signer: MockSlowSigner(
          innerSigner: Bip340EventSigner(
            privateKey: key.privateKey!,
            publicKey: key.publicKey,
          ),
          delay: const Duration(seconds: 12),
        ),
      );

      final event = Nip01Event(
        pubKey: key.publicKey,
        kind: Nip01Event.kTextNoteKind,
        tags: [],
        content: "test",
      );

      // timeout (10s) < signing (12s) → should fail without fix
      final result = await ndk.broadcast
          .broadcast(
            nostrEvent: event,
            specificRelays: [relay.url],
            timeout: const Duration(seconds: 10),
          )
          .broadcastDoneFuture;

      expect(result.any((r) => r.broadcastSuccessful), isTrue);

      await ndk.destroy();
      await relay.stop();
    },
  );

  test(
    'request with AUTH should not timeout during signing',
    timeout: Timeout(Duration(seconds: 60)),
    () async {
      final key = Bip340.generatePrivateKey();
      final relay = MockRelay(name: "relay", requireAuthForRequests: true);

      final testEvent =
          await Bip340EventSigner(
            privateKey: key.privateKey!,
            publicKey: key.publicKey,
          ).sign(
            Nip01Event(
              pubKey: key.publicKey,
              kind: Nip01Event.kTextNoteKind,
              tags: [],
              content: "test event",
            ),
          );

      await relay.start(events: [testEvent]);

      final ndk = Ndk(
        NdkConfig(
          authHandler: (_, _) async => true,
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relay.url],
        ),
      );
      await ndk.bootstrapRelaysConnected;

      ndk.accounts.loginExternalSigner(
        signer: MockSlowSigner(
          innerSigner: Bip340EventSigner(
            privateKey: key.privateKey!,
            publicKey: key.publicKey,
          ),
          delay: const Duration(seconds: 12),
        ),
      );

      // timeout (10s) < signing (12s) → should fail without fix
      final result = await ndk.requests
          .query(
            filter: Filter(kinds: [Nip01Event.kTextNoteKind]),
            explicitRelays: [relay.url],
            timeout: const Duration(seconds: 10),
          )
          .future;

      expect(result, isNotEmpty);

      await ndk.destroy();
      await relay.stop();
    },
  );
}
