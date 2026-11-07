import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/mock_event_verifier.dart';

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String reason = 'condition never became true',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(reason);
}

void main() {
  test(
    'a query retrying its authentication is not closed by another relay',
    timeout: const Timeout(Duration(seconds: 120)),
    () async {
      final key = Bip340.generatePrivateKey();
      final note = Nip01Event(
        kind: Nip01Event.kTextNoteKind,
        pubKey: key.publicKey,
        content: "served after the reconnect",
        tags: [],
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final authRelay = MockRelay(
        name: "relay requiring auth",
        requireAuthForRequests: true,

        // the authentication the query waits on is still unanswered when the
        // relay goes away, so it fails while the connection has no socket
        unansweredAuths: 1,
      );
      final slowRelay = MockRelay(name: "slow relay");
      await authRelay.start(events: [note]);
      // answers late enough for its EOSE to land while the other relay is gone
      await slowRelay.start(delayResponse: const Duration(seconds: 5));

      final ndk = Ndk(
        NdkConfig(
          authHandler: (_, _) async => true,
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [authRelay.url, slowRelay.url],
        ),
      );
      ndk.accounts.loginPrivateKey(
        pubkey: key.publicKey,
        privkey: key.privateKey!,
      );

      final response = ndk.requests.query(
        filter: Filter(authors: [key.publicKey]),
        timeout: const Duration(seconds: 60),
      );

      await _waitUntil(
        () => authRelay.received('AUTH').length == 1,
        reason: 'the query never authenticated',
      );

      await authRelay.stop();
      // the EOSE of the other relay lands here, on a request whose last relay
      // is retrying its authentication on a socket that is not back yet
      await Future<void>.delayed(const Duration(seconds: 6));
      await authRelay.start(events: [note]);

      final events = await response.future;

      expect(
        events.map((e) => e.content),
        contains("served after the reconnect"),
        reason:
            'a request retrying its authentication must outlive the relays '
            'that finished, and be replayed once its connection is back',
      );

      await ndk.destroy();
      await authRelay.stop();
      await slowRelay.stop();
    },
  );
}
