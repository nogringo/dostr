import 'package:ndk/ndk.dart';
import 'package:ndk_mock_relay/ndk_mock_relay.dart';
import 'package:test/test.dart';

void main() {
  late MockRelay relay;

  setUp(() async {
    relay = MockRelay(name: 'limited', maxMessageLength: 64 * 1024);
    await relay.start();
  });

  tearDown(() => relay.stop());

  Future<void> query(
    Filter filter, {
    MessageLengthLimit? messageLengthLimit,
  }) async {
    final ndk = Ndk(
      NdkConfig(
        cache: MemCacheManager(),
        eventVerifier: Bip340EventVerifier(),
        bootstrapRelays: [],
        messageLengthLimit: messageLengthLimit,
      ),
    );
    addTearDown(ndk.destroy);
    await ndk.requests
        .query(filter: filter, explicitRelays: [relay.url])
        .future;
  }

  test(
    'a filter longer than the NIP-11 max_message_length is not sent',
    () async {
      await query(
        Filter(
          authors: [
            for (var i = 0; i < 1600; i++) i.toRadixString(16).padLeft(64, '0'),
          ],
        ),
      );

      expect(relay.received('REQ'), isEmpty);
      expect(relay.oversizedMessages, 0);
    },
  );

  test('NdkConfig.messageLengthLimit comes before NIP-11', () async {
    await query(Filter(kinds: [1]), messageLengthLimit: (_) => 10);

    expect(relay.received('REQ'), isEmpty);
  });
}
