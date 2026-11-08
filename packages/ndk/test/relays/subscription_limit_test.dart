import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

void main() {
  late MockRelay relay;

  setUp(() async {
    relay = MockRelay(name: 'limited', maxSubscriptions: 2);
    await relay.start();
  });

  tearDown(() => relay.stop());

  Future<void> queryFive({SubscriptionLimit? subscriptionLimit}) async {
    final ndk = Ndk(
      NdkConfig(
        cache: MemCacheManager(),
        eventVerifier: Bip340EventVerifier(),
        bootstrapRelays: [],
        subscriptionLimit: subscriptionLimit,
      ),
    );
    addTearDown(ndk.destroy);
    await Future.wait([
      for (var kind = 0; kind < 5; kind++)
        ndk.requests
            .query(
              filter: Filter(kinds: [kind]),
              explicitRelays: [relay.url],
            )
            .future,
    ]);
  }

  test('a relay gets no more REQs than its NIP-11 max_subscriptions', () async {
    await queryFive();

    expect(relay.refusedRequests, 0);
    expect(relay.clients.single.mostSubscriptions, 2);
  });

  test('NdkConfig.subscriptionLimit comes before NIP-11', () async {
    await queryFive(subscriptionLimit: (_) => 1);

    expect(relay.clients.single.mostSubscriptions, 1);
  });

  test('a null NdkConfig.subscriptionLimit falls back on NIP-11', () async {
    await queryFive(subscriptionLimit: (_) => null);

    expect(relay.refusedRequests, 0);
    expect(relay.clients.single.mostSubscriptions, 2);
  });
}
