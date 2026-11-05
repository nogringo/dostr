import 'dart:async';

import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import '../../../cashu/test/mocks/mock_event_verifier.dart';
import '../mocks/mock_relay.dart';

Future<void> _waitUntil(bool Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(reason);
}

class _UnreadableCache extends MemCacheManager {
  @override
  Future<List<Nip01Event>> loadEvents({
    List<String>? ids,
    List<String>? pubKeys,
    List<int>? kinds,
    Map<String, List<String>>? tags,
    int? since,
    int? until,
    String? search,
    int? limit,
  }) => Future.error(StateError('cache unavailable'));
}

void main() {
  final key = Bip340.generatePrivateKey();
  final filter = Filter(
    kinds: [Nip01Event.kTextNoteKind],
    authors: [key.publicKey],
  );

  Nip01Event note(String content) => Bip340.signEvent(
    event: Nip01Event(
      pubKey: key.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: [],
      content: content,
    ),
    privateKey: key.privateKey!,
  );

  Ndk buildNdk({CacheManager? cache}) => Ndk(
    NdkConfig(
      eventVerifier: MockEventVerifier(),
      cache: cache ?? MemCacheManager(),
      bootstrapRelays: [],
    ),
  );

  group('identical subscriptions', () {
    late MockRelay relay;
    late Ndk ndk;

    setUp(() async {
      relay = MockRelay(name: 'relay', signEvents: false);
      await relay.startServer();
      ndk = buildNdk();
    });

    tearDown(() async {
      await ndk.destroy();
      await relay.stopServer();
    });

    NdkResponse subscribe() => ndk.requests.subscription(
      filter: filter.clone(),
      explicitRelays: [relay.url],
      cacheRead: true,
    );

    Future<Nip01Event> nextEvent(NdkResponse response) {
      final next = Completer<Nip01Event>();
      late final StreamSubscription<Nip01Event> listening;
      listening = response.stream.listen((event) {
        if (next.isCompleted) return;
        next.complete(event);
        listening.cancel();
      });
      return next.future.timeout(const Duration(seconds: 3));
    }

    for (final closeFirst in [true, false]) {
      final closed = closeFirst ? 'first' : 'second';
      test('closing the $closed one keeps the other live', () async {
        final first = subscribe();
        final second = subscribe();
        await _waitUntil(
          () => relay.activeSubscriptionCount == 1,
          'the relay never got the subscription',
        );
        expect(
          relay.totalRequestedSubscriptionCount,
          1,
          reason: 'identical subscriptions share one REQ',
        );

        final (gone, kept) = closeFirst ? (first, second) : (second, first);
        await ndk.requests.closeSubscription(gone.requestId);
        expect(relay.activeSubscriptionCount, 1);

        final live = note('after one closed');
        final received = nextEvent(kept);
        relay.sendEvent(event: live, subId: first.requestId);
        expect((await received).id, live.id);

        await ndk.requests.closeSubscription(kept.requestId);
        await _waitUntil(
          () => relay.activeSubscriptionCount == 0,
          'the last one closing never sent the CLOSE',
        );
      });
    }
  });

  test('a query whose cache cannot be read still asks its relays', () async {
    final stored = note('stored on the relay');
    final relay = MockRelay(name: 'relay', signEvents: false);
    await relay.startServer(textNotes: {key: stored});
    addTearDown(relay.stopServer);
    final ndk = buildNdk(cache: _UnreadableCache());
    addTearDown(ndk.destroy);

    final response = ndk.requests.query(
      filter: filter,
      explicitRelays: [relay.url],
      cacheWrite: false,
    );

    final events = await response.future.timeout(const Duration(seconds: 5));
    expect(events.map((e) => e.id), [stored.id]);
  });
}
