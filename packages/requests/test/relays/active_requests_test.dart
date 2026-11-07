import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

import '../mocks/requests_client.dart';

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
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(reason);
}

Map<RelayConnectionKey, int> _activeRequests(RequestsClient ndk) => {
  for (final entry in ndk.relays.connectivities.entries)
    entry.key: entry.value.stats.activeRequests,
};

void main() {
  test('a query leaves no active request behind', () async {
    final relay = MockRelay(name: "relay");
    await relay.start();

    final ndk = RequestsClient(
      eventVerifier: Bip340EventVerifier(),
      cache: MemCacheManager(),
      bootstrapRelays: [relay.url],
    );

    final response = ndk.requests.query(
      filter: Filter(kinds: [Nip01Event.kTextNoteKind]),
    );
    await response.future;
    await ndk.requests.closeSubscription(response.requestId);

    expect(_activeRequests(ndk).values, everyElement(0));

    await ndk.destroy();
    await relay.stop();
  });

  test(
    'a subscription re-routed for auth is counted on the connection carrying it',
    timeout: const Timeout(Duration(seconds: 60)),
    () async {
      final key = Bip340.generatePrivateKey();
      final relay = MockRelay(
        name: "relay requiring auth",
        requireAuthForRequests: true,
      );
      await relay.start();

      final ndk = RequestsClient(
        authHandler: (_, _) async => true,
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [relay.url],
      );
      ndk.accounts.loginPrivateKey(
        pubkey: key.publicKey,
        privkey: key.privateKey!,
      );

      final response = ndk.requests.subscription(
        filter: Filter(kinds: [Nip01Event.kTextNoteKind]),
      );
      final subId = response.requestId;

      await _waitUntil(
        () => relay.subscriptionsAuthenticatedAs(key.publicKey).contains(subId),
        reason: 'the subscription never reached an authenticated connection',
      );

      // the anonymous connection was refused, the bound one carries it
      expect(_activeRequests(ndk), {
        RelayConnectionKey.anonymous(relay.url): 0,
        RelayConnectionKey.authenticated(relay.url, key.publicKey): 1,
      });

      await ndk.requests.closeSubscription(subId);

      expect(_activeRequests(ndk).values, everyElement(0));

      await ndk.destroy();
      await relay.stop();
    },
  );
}
