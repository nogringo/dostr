import 'dart:async';

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
}

void main() {
  const url = 'wss://relay.example';
  final info = RelayInfo.fromJson({'name': 'Example'});
  late _Repo repo;
  late CachedRelayInfoRepo cached;

  setUp(() {
    repo = _Repo();
    cached = CachedRelayInfoRepo(repo);
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

  test('an answer is fetched again once maxAge passes', () async {
    cached = CachedRelayInfoRepo(
      repo,
      maxAge: const Duration(milliseconds: 50),
    );
    repo.next.complete(info);
    await cached.getRelayInfo(url);
    await cached.getRelayInfo(url);
    expect(repo.requested, [url]);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    await cached.getRelayInfo(url);
    expect(repo.requested, [url, url]);
  });

  test('maxAge counts from the answer, not the request', () async {
    cached = CachedRelayInfoRepo(
      repo,
      maxAge: const Duration(milliseconds: 10),
    );
    final first = cached.getRelayInfo(url);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final second = cached.getRelayInfo(url);
    repo.next.complete(info);

    expect(await first, same(info));
    expect(await second, same(info));
    expect(repo.requested, [url]);
  });

  test('a throwing repo is retried on the next call', () async {
    repo.next.completeError(StateError('offline'));
    await expectLater(cached.getRelayInfo(url), throwsStateError);

    repo.next = Completer()..complete(info);
    expect(await cached.getRelayInfo(url), same(info));
  });

  test('a fetch that throws keeps throwing for failureMaxAge', () async {
    cached = CachedRelayInfoRepo(
      repo,
      failureMaxAge: const Duration(milliseconds: 50),
    );
    repo.next.completeError(StateError('offline'));
    await expectLater(cached.getRelayInfo(url), throwsStateError);
    await expectLater(cached.getRelayInfo(url), throwsStateError);
    expect(repo.requested, [url]);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    repo.next = Completer()..complete(info);
    expect(await cached.getRelayInfo(url), same(info));
    expect(repo.requested, [url, url]);
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
