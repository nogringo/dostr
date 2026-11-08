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
}
