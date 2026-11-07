import 'dart:async';

import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';

import '../../mocks/mock_event_verifier.dart';

/// A second REQ with the same id replaces the first on the relay (NIP-01), so
/// whatever an engine routes to one relay has to travel in a single REQ.
void main() {
  final a = Bip340.generatePrivateKey();
  final b = Bip340.generatePrivateKey();

  Nip01Event note(KeyPair key) => Bip340.signEvent(
    event: Nip01Event(
      pubKey: key.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: [],
      content: 'live note',
    ),
    privateKey: key.privateKey!,
  );

  test(
    'a JIT subscription keeps every pubkey it routed to one relay',
    () async {
      final relay = MockRelay(name: 'relay');
      await relay.start();
      addTearDown(relay.stop);

      // a is covered by the relay's NIP-65 entry, b by nothing, so b is blasted
      // to the same bootstrap relay
      final cache = MemCacheManager();
      await cache.saveUserRelayLists([
        UserRelayList.fromNip65(
          Nip65.fromMap(a.publicKey, {relay.url: ReadWriteMarker.readWrite}),
        ),
      ]);
      final ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: cache,
          engine: NdkEngine.JIT,
          bootstrapRelays: [relay.url],
        ),
      );
      addTearDown(ndk.destroy);
      final publisher = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [],
        ),
      );
      addTearDown(publisher.destroy);

      final subscription = ndk.requests.subscription(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [a.publicKey, b.publicKey],
        ),
        desiredCoverage: 1,
      );
      final authors = <String>{};
      final both = Completer<void>();
      subscription.stream.listen((event) {
        authors.add(event.pubKey);
        if (authors.length == 2 && !both.isCompleted) both.complete();
      });
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (relay.activeSubscriptionCount == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      for (final key in [a, b]) {
        await publisher.broadcast
            .broadcast(nostrEvent: note(key), specificRelays: [relay.url])
            .broadcastDoneFuture;
      }

      await both.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => fail('live notes only arrived from $authors'),
      );
    },
  );
}
