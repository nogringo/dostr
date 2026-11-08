import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:ndk_nip11/ndk_nip11.dart';
import 'package:test/test.dart';

class _Repo implements RelayInfoRepo {
  final requested = <String>[];
  Completer<RelayInfo?> next = Completer();

  @override
  Future<RelayInfo?> getRelayInfo(String url) {
    requested.add(url);
    return next.future;
  }

  void answer(RelayInfo? info) => next = Completer()..complete(info);

  void fail() => next = Completer()..completeError(StateError('offline'));
}

const _pending = #pending;

/// what [future] completed with once the microtasks ran, its error included
Object? _outcome(FakeAsync async, Future<RelayInfo?> future) {
  Object? outcome = _pending;
  future.then<void>(
    (info) => outcome = info,
    onError: (Object error) => outcome = error,
  );
  async.flushMicrotasks();
  return outcome;
}

void main() {
  const url = 'wss://relay.example';
  const minute = Duration(minutes: 1);
  final info = RelayInfo.fromJson({'name': 'Example'});
  final updated = RelayInfo.fromJson({'name': 'Updated'});
  late _Repo repo;
  late CachedRelayInfoRepo cached;

  setUp(() {
    repo = _Repo();
    cached = CachedRelayInfoRepo(repo);
  });

  void fake(
    void Function(FakeAsync async) body, {
    Duration? maxAge,
    Duration? failureMaxAge,
  }) => fakeAsync((async) {
    cached = CachedRelayInfoRepo(
      repo,
      maxAge: maxAge,
      failureMaxAge: failureMaxAge,
      stopwatch: clock.stopwatch(),
    );
    body(async);
  });

  test('concurrent and later calls share one fetch per relay', () async {
    final first = cached.getRelayInfo(url);
    final second = cached.getRelayInfo(url);
    repo.next.complete(info);

    expect(await first, same(info));
    expect(await second, same(info));
    expect(await cached.getRelayInfo(url), same(info));
    expect(repo.requested, [url]);
  });

  test('each relay gets its own fetch', () async {
    repo.next.complete(info);
    await cached.getRelayInfo(url);
    await cached.getRelayInfo('wss://other.example');

    expect(repo.requested, [url, 'wss://other.example']);
  });

  test('a relay without document is remembered', () async {
    repo.next.complete(null);
    expect(await cached.getRelayInfo(url), isNull);
    expect(await cached.getRelayInfo(url), isNull);
    expect(repo.requested, [url]);
  });

  test('an answer is fetched again once maxAge passes', () {
    fake(maxAge: minute, (async) {
      repo.answer(info);
      expect(_outcome(async, cached.getRelayInfo(url)), same(info));
      async.elapse(minute - const Duration(seconds: 1));
      expect(_outcome(async, cached.getRelayInfo(url)), same(info));
      expect(repo.requested, [url]);

      async.elapse(const Duration(seconds: 1));
      repo.answer(updated);
      expect(_outcome(async, cached.getRelayInfo(url)), same(updated));
      expect(repo.requested, [url, url]);
    });
  });

  test('maxAge counts from the answer, not the request', () {
    fake(maxAge: minute, (async) {
      repo.next = Completer();
      final first = cached.getRelayInfo(url);
      async.elapse(minute * 2);
      final second = cached.getRelayInfo(url);
      repo.next.complete(info);

      expect(_outcome(async, first), same(info));
      expect(_outcome(async, second), same(info));
      async.elapse(minute - const Duration(seconds: 1));
      expect(_outcome(async, cached.getRelayInfo(url)), same(info));
      expect(repo.requested, [url]);
    });
  });

  test('a throwing repo is retried on the next call', () async {
    repo.next.completeError(StateError('offline'));
    await expectLater(cached.getRelayInfo(url), throwsStateError);

    repo.answer(info);
    expect(await cached.getRelayInfo(url), same(info));
  });

  test('a fetch that throws keeps throwing for failureMaxAge', () {
    fake(failureMaxAge: minute, (async) {
      repo.fail();
      expect(_outcome(async, cached.getRelayInfo(url)), isStateError);
      async.elapse(minute - const Duration(seconds: 1));
      expect(_outcome(async, cached.getRelayInfo(url)), isStateError);
      expect(repo.requested, [url]);

      async.elapse(const Duration(seconds: 1));
      repo.answer(info);
      expect(_outcome(async, cached.getRelayInfo(url)), same(info));
      expect(repo.requested, [url, url]);
    });
  });

  test('a refresh that throws serves the last answer until one comes', () {
    fake(maxAge: minute, failureMaxAge: minute, (async) {
      repo.answer(info);
      _outcome(async, cached.getRelayInfo(url));

      async.elapse(minute);
      repo.fail();
      expect(_outcome(async, cached.getRelayInfo(url)), same(info));
      expect(_outcome(async, cached.getRelayInfo(url)), same(info));
      expect(repo.requested, [url, url]);

      async.elapse(minute);
      expect(_outcome(async, cached.getRelayInfo(url)), same(info));
      expect(repo.requested, [url, url, url]);

      async.elapse(minute);
      repo.answer(updated);
      expect(_outcome(async, cached.getRelayInfo(url)), same(updated));
    });
  });

  test('a refresh that throws keeps an answer without document', () {
    fake(maxAge: minute, (async) {
      repo.answer(null);
      _outcome(async, cached.getRelayInfo(url));

      async.elapse(minute);
      repo.fail();
      expect(_outcome(async, cached.getRelayInfo(url)), isNull);
      expect(repo.requested, [url, url]);
    });
  });

  test('sweeping the failures of other relays keeps the answers', () {
    fake(maxAge: minute, (async) {
      repo.answer(info);
      _outcome(async, cached.getRelayInfo(url));
      async.elapse(minute);

      repo.fail();
      for (var i = 0; i < 300; i++) {
        _outcome(async, cached.getRelayInfo('wss://down$i.example'));
      }
      expect(_outcome(async, cached.getRelayInfo(url)), same(info));
    });
  });

  test('evict forgets one relay and clear forgets them all', () async {
    const other = 'wss://other.example';
    repo.next.complete(info);
    await cached.getRelayInfo(url);
    await cached.getRelayInfo(other);

    cached.evict(url);
    await cached.getRelayInfo(url);
    await cached.getRelayInfo(other);
    expect(repo.requested, [url, other, url]);

    cached.clear();
    await cached.getRelayInfo(url);
    await cached.getRelayInfo(other);
    expect(repo.requested, [url, other, url, url, other]);
  });

  test('evict forgets the answer a failure would serve', () async {
    repo.answer(info);
    await cached.getRelayInfo(url);
    cached.evict(url);

    repo.fail();
    await expectLater(cached.getRelayInfo(url), throwsStateError);
  });

  test('a fetch evicted while it runs does not touch the next one', () async {
    cached = CachedRelayInfoRepo(repo, failureMaxAge: const Duration(hours: 1));
    final first = repo.next;
    final evicted = cached.getRelayInfo(url);
    cached.evict(url);
    repo.next = Completer();
    final next = cached.getRelayInfo(url);

    first.completeError(StateError('offline'));
    await expectLater(evicted, throwsStateError);
    repo.next.complete(info);
    expect(await next, same(info));
    expect(await cached.getRelayInfo(url), same(info));
    expect(repo.requested, [url, url]);
  });
}
