import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/requests_client.dart';
import '../mocks/mock_event_verifier.dart';

/// a request sent to zero relays has nothing to wait for and must not hang
/// until the query timeout
void main() {
  const queryTimeout = Duration(seconds: 10);
  const maxAcceptable = Duration(seconds: 5);

  Future<void> expectFastEmptyQuery(RequestsClient ndk) async {
    bool timeoutTriggered = false;

    final stopwatch = Stopwatch()..start();
    final response = ndk.requests.query(
      filter: Filter(kinds: [Nip01Event.kTextNoteKind]),
      timeout: queryTimeout,
      timeoutCallback: () {
        timeoutTriggered = true;
      },
    );

    final events = await response.future;
    stopwatch.stop();

    expect(events, isEmpty);
    expect(timeoutTriggered, isFalse);
    expect(stopwatch.elapsed, lessThan(maxAcceptable));
  }

  group('no relay - query does not wait for the timeout', () {
    late RequestsClient ndk;

    tearDown(() async {
      await ndk.destroy();
    });

    test('relay sets engine', () async {
      ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.relaySets,
        bootstrapRelays: [],
      );

      await expectFastEmptyQuery(ndk);
    });

    test('jit engine', () async {
      ndk = RequestsClient(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        engine: Engine.jit,
        bootstrapRelays: [],
      );

      await expectFastEmptyQuery(ndk);
    });
  });
}
