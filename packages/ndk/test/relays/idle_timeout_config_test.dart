import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

void main() {
  test('NdkConfig idle timeouts reach the relay connections', () async {
    final relay = MockRelay(name: 'idle');
    await relay.start();
    addTearDown(relay.stop);
    final ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [relay.url],
        anonymousConnectionIdleTimeout: const Duration(milliseconds: 300),
      ),
    );
    addTearDown(ndk.destroy);

    await ndk.requests.query(filter: Filter(kinds: [1])).future;
    expect(ndk.relays.isRelayConnected(relay.url), isTrue);

    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (ndk.relays.connectivities.isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the idle connection was never closed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
}
