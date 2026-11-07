import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/requests_client.dart';
import '../mocks/mock_event_verifier.dart';
import '../mocks/nip65_events.dart';

void main() {
  test(
    'a relay connecting after the request ended does not revive it',
    () async {
      final key1 = Bip340.generatePrivateKey();
      final note = Nip01Event(
        kind: Nip01Event.kTextNoteKind,
        pubKey: key1.publicKey,
        content: "note from key1",
        tags: [],
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final fast = MockRelay(name: "fast relay");
      final slow = MockRelay(name: "slow relay");

      final nip65 = Nip65.fromMap(key1.publicKey, {
        fast.url: ReadWriteMarker.readWrite,
        slow.url: ReadWriteMarker.readWrite,
      });

      await fast.start(
        events: [
          note,
          ...nip65Events({key1: nip65}),
        ],
      );
      await slow.start(
        events: [
          note,
          ...nip65Events({key1: nip65}),
        ],
        // the pubkey strategy connects to this one without holding the request
        // open, so it is long over by the time the connection is up
        delayConnection: Duration(seconds: 2),
      );

      final ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.jit,
        bootstrapRelays: [fast.url],
      );

      await ndk.cache.saveUserRelayList(UserRelayList.fromNip65(nip65));

      final response = ndk.requests.query(
        filter: Filter(
          kinds: [Nip01Event.kTextNoteKind],
          authors: [key1.publicKey],
        ),
      );
      expect(await response.future, isNotEmpty);

      await Future.delayed(Duration(seconds: 3));

      expect(
        ndk.relayReqs.openIds,
        isNot(contains(response.requestId)),
        reason: 'a request that already ended must not come back in flight',
      );
      expect(
        slow.connectionsThatRequested(response.requestId),
        0,
        reason: 'a REQ sent after the request ended is one nobody would CLOSE',
      );

      await ndk.destroy();
      await fast.stop();
      await slow.stop();
    },
  );
}
