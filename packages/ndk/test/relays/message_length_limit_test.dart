import 'dart:convert';
import 'dart:io';

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

  final hundredKilobytes = Filter(
    authors: [
      for (var i = 0; i < 1600; i++) i.toRadixString(16).padLeft(64, '0'),
    ],
  );

  Future<void> query(
    Filter filter, {
    MockRelay? on,
    CacheManager? cache,
    MessageLengthLimit? messageLengthLimit,
  }) async {
    final ndk = Ndk(
      NdkConfig(
        cache: cache ?? MemCacheManager(),
        eventVerifier: Bip340EventVerifier(),
        bootstrapRelays: [],
        messageLengthLimit: messageLengthLimit,
      ),
    );
    try {
      await ndk.requests
          .query(filter: filter, explicitRelays: [(on ?? relay).url])
          .future;
    } finally {
      await ndk.destroy();
    }
  }

  test(
    'a filter longer than the NIP-11 max_message_length is not sent',
    () async {
      await query(hundredKilobytes);

      expect(relay.received('REQ'), isEmpty);
      expect(relay.oversizedMessages, 0);
    },
  );

  test('NdkConfig.messageLengthLimit comes before NIP-11', () async {
    await query(Filter(kinds: [1]), messageLengthLimit: (_) => 10);

    expect(relay.received('REQ'), isEmpty);
  });

  test(
    'a limit learned from a 1009 is kept in the cache across restarts',
    () async {
      final unpublished = MockRelay(name: 'unpublished');
      unpublished.onMessage = (client, message) {
        if (utf8.encode(jsonEncode(message)).length <= 64 * 1024) return false;
        client.close(WebSocketStatus.messageTooBig);
        return true;
      };
      await unpublished.start();
      addTearDown(unpublished.stop);
      final cache = MemCacheManager();

      await query(hundredKilobytes, on: unpublished, cache: cache);
      expect(cache.learnedMessageLengths, hasLength(1));
      await query(hundredKilobytes, on: unpublished, cache: cache);

      expect(unpublished.received('REQ'), hasLength(1));
    },
  );
}
