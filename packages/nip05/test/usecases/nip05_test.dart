import 'dart:async';
import 'dart:convert';

import 'package:dostr_nip05/dostr_nip05.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../mocks/memory_nip05_cache.dart';

const pubkey =
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
const otherPubkey =
    'e247d5da03bab4206b4d6ef5d9db0e175e0dbf51585fa16345dd53abdd2d9259';

const usernameJson = {
  'names': {'username': pubkey},
  'relays': {
    pubkey: ['wss://relay1.test', 'wss://relay2.test'],
  },
};

const rootJson = {
  'names': {'_': pubkey},
};

http.Response nostrJson(Object? json) => http.Response(jsonEncode(json), 200);

/// A resolver on [cache] whose domains answer with [handler], and the
/// requests it sent
({Nip05Resolver resolver, MemoryNip05Cache cache, List<http.Request> requests})
setup(
  FutureOr<http.Response> Function(http.Request request) handler, {
  MemoryNip05Cache? cache,
}) {
  final requests = <http.Request>[];
  final usedCache = cache ?? MemoryNip05Cache();
  final resolver = Nip05Resolver(
    cache: usedCache,
    httpClient: MockClient((request) async {
      requests.add(request);
      return handler(request);
    }),
  );
  return (resolver: resolver, cache: usedCache, requests: requests);
}

Nip05Record record(
  String identifier,
  String? pubkey, {
  required Duration age,
}) => Nip05Record(
  identifier: identifier,
  nip05: pubkey == null ? null : Nip05(identifier: identifier, pubkey: pubkey),
  fetchedAt: DateTime.now().subtract(age),
);

void main() {
  group('resolve', () {
    test('returns the pubkey and relays of the name', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
      );

      final result = await resolver.resolve('username@example.com');

      final data = (result as Nip05Found).data;
      expect(data.identifier, 'username@example.com');
      expect(data.pubkey, pubkey);
      expect(data.relays, ['wss://relay1.test', 'wss://relay2.test']);
      expect(requests.single.url.host, 'example.com');
      expect(requests.single.url.path, '/.well-known/nostr.json');
      expect(requests.single.url.queryParameters['name'], 'username');
    });

    test('returns Nip05NotFound when the name is absent', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson({'names': {}}),
      );

      expect(await resolver.resolve('ghost@example.com'), isA<Nip05NotFound>());
    });

    test('returns Nip05NotFound on HTTP 404', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => http.Response('', 404),
      );

      expect(await resolver.resolve('ghost@example.com'), isA<Nip05NotFound>());
    });

    test('does not fall back to the _ entry', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson(rootJson),
      );

      expect(await resolver.resolve('alice@domain.test'), isA<Nip05NotFound>());
    });

    test('a bare domain resolves as _@domain', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(rootJson),
      );

      final result = await resolver.resolve('domain.test');

      expect(requests.single.url.queryParameters['name'], '_');
      expect((result as Nip05Found).data.identifier, '_@domain.test');
    });

    test('lowercases the identifier', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
      );

      final result = await resolver.resolve('UserName@Example.com');

      expect(requests.single.url.host, 'example.com');
      expect(requests.single.url.queryParameters['name'], 'username');
      expect(result, isA<Nip05Found>());
    });

    test('lowercases a pubkey given in uppercase hex', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson({
          'names': {'username': pubkey.toUpperCase()},
        }),
      );

      final result = await resolver.resolve('username@example.com');

      expect((result as Nip05Found).data.pubkey, pubkey);
    });

    test('finds a name the domain gives in another case', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson({
          'names': {'UserName': pubkey},
        }),
      );

      final result = await resolver.resolve('username@example.com');

      final data = (result as Nip05Found).data;
      expect(data.identifier, 'username@example.com');
      expect(data.pubkey, pubkey);
    });

    test('prefers the name in lowercase to one in another case', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson({
          'names': {'UserName': otherPubkey, 'username': pubkey},
        }),
      );

      final result = await resolver.resolve('username@example.com');

      expect((result as Nip05Found).data.pubkey, pubkey);
    });

    test(
      'returns Nip05ResolveInvalidResponse for a pubkey that is not hex',
      () async {
        for (final entry in <Object>[
          'npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6',
          'pubkey',
          '${pubkey}00',
          42,
        ]) {
          final (:resolver, cache: _, requests: _) = setup(
            (_) => nostrJson({
              'names': {'username': entry},
            }),
          );

          expect(
            await resolver.resolve('username@example.com'),
            isA<Nip05ResolveInvalidResponse>(),
            reason: '$entry',
          );
        }
      },
    );

    test(
      'returns Nip05ResolveInvalidResponse when names is not an object',
      () async {
        for (final json in [
          {'relays': {}},
          {'names': []},
          {'names': 'username'},
          [usernameJson],
        ]) {
          final (:resolver, cache: _, requests: _) = setup(
            (_) => nostrJson(json),
          );

          expect(
            await resolver.resolve('username@example.com'),
            isA<Nip05ResolveInvalidResponse>(),
            reason: '$json',
          );
        }
      },
    );

    test('returns Nip05ResolveInvalidResponse on malformed JSON', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => http.Response('not json', 200),
      );

      expect(
        await resolver.resolve('username@example.com'),
        isA<Nip05ResolveInvalidResponse>(),
      );
    });

    test('returns Nip05ResolveNetworkError on HTTP error', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => http.Response('', 500),
      );

      final result = await resolver.resolve('username@example.com');

      expect(result, isA<Nip05ResolveNetworkError>());
      expect((result as Nip05ResolveError).cause, isA<http.ClientException>());
    });

    test('does not follow redirects', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => http.Response('', 301, headers: {'location': 'https://x.test'}),
      );

      final result = await resolver.resolve('username@example.com');

      expect(requests.single.followRedirects, false);
      expect(result, isA<Nip05ResolveNetworkError>());
    });

    test('reads missing or mistyped relays as none', () async {
      for (final relays in <Object?>[
        null,
        [],
        'wss://relay.test',
        {pubkey: 'wss://relay.test'},
        {pubkey: null},
        {
          otherPubkey: ['wss://relay.test'],
        },
      ]) {
        final (:resolver, cache: _, requests: _) = setup(
          (_) => nostrJson({
            'names': {'username': pubkey},
            'relays': ?relays,
          }),
        );

        final result = await resolver.resolve('username@example.com');

        expect((result as Nip05Found).data.relays, isEmpty, reason: '$relays');
      }
    });

    test('normalizes the relays and keeps each once', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson({
          'names': {'username': pubkey},
          'relays': {
            pubkey: [
              'wss://Relay.Example.com/',
              42,
              'https://not-a-relay.test',
              'wss://relay.example.com',
              'wss://other.test',
            ],
          },
        }),
      );

      final result = await resolver.resolve('username@example.com');

      expect((result as Nip05Found).data.relays, [
        'wss://relay.example.com',
        'wss://other.test',
      ]);
    });

    test('returns Nip05NotFound for an identifier that is not a NIP-05 one, '
        'without a request', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
      );

      for (final identifier in [
        '',
        'bob',
        'bob@localhost',
        'a@b@example.com',
        'a&name=_@example.com',
        'bob+tag@example.com',
        'bob@evil.com/x',
        'bob@evil.com?a=1',
        'bob@[::1]',
        'bob@exa mple.com',
        'bob@exämple.com',
      ]) {
        expect(
          await resolver.resolve(identifier),
          isA<Nip05NotFound>(),
          reason: identifier,
        );
      }
      expect(requests, isEmpty);
    });
  });

  group('cache', () {
    test('keeps results in memory without a cache', () async {
      var requests = 0;
      final resolver = Nip05Resolver(
        httpClient: MockClient((_) async {
          requests++;
          return nostrJson(usernameJson);
        }),
      );

      await resolver.resolve('username@example.com');
      final second = await resolver.resolve('username@example.com');

      expect(second, isA<Nip05Found>());
      expect(requests, 1);
    });

    test('identifiers differing in case share one cache entry', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
      );

      final first = await resolver.resolve(' UserName@Example.com ');
      final second = await resolver.resolve('username@example.com');

      expect(requests, hasLength(1));
      expect((first as Nip05Found).data.identifier, 'username@example.com');
      expect(second, isA<Nip05Found>());
    });

    test('uses a fresh Nip05Found', () async {
      final cache = MemoryNip05Cache();
      cache.records['username@example.com'] = record(
        'username@example.com',
        otherPubkey,
        age: nip05ValidDuration - const Duration(minutes: 1),
      );
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
        cache: cache,
      );

      final result = await resolver.resolve('username@example.com');

      expect((result as Nip05Found).data.pubkey, otherPubkey);
      expect(requests, isEmpty);
    });

    test('refetches a Nip05Found once nip05ValidDuration is over', () async {
      final cache = MemoryNip05Cache();
      cache.records['username@example.com'] = record(
        'username@example.com',
        otherPubkey,
        age: nip05ValidDuration,
      );
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
        cache: cache,
      );

      final first = await resolver.resolve('username@example.com');
      final second = await resolver.resolve('username@example.com');

      expect((first as Nip05Found).data.pubkey, pubkey);
      expect((second as Nip05Found).data.pubkey, pubkey);
      expect(requests, hasLength(1));
    });

    test('remembers a Nip05NotFound', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => http.Response('', 404),
      );

      final first = await resolver.resolve('me@github.com');
      final second = await resolver.resolve('Me@GitHub.com');

      expect(requests, hasLength(1));
      expect(first, isA<Nip05NotFound>());
      expect(second, isA<Nip05NotFound>());
    });

    test('persists a Nip05NotFound', () async {
      final (resolver: first, :cache, :requests) = setup(
        (_) => http.Response('', 404),
      );
      await first.resolve('me@github.com');
      final (resolver: second, cache: _, requests: later) = setup(
        (_) => http.Response('', 404),
        cache: cache,
      );

      final result = await second.resolve('me@github.com');

      expect(requests, hasLength(1));
      expect(later, isEmpty);
      expect(result, isA<Nip05NotFound>());
      expect(cache.records['me@github.com']!.nip05, isNull);
    });

    test(
      'refetches a Nip05NotFound once nip05NotFoundDuration is over',
      () async {
        final cache = MemoryNip05Cache();
        cache.records['username@example.com'] = record(
          'username@example.com',
          null,
          age: nip05NotFoundDuration,
        );
        final (:resolver, cache: _, requests: _) = setup(
          (_) => nostrJson(usernameJson),
          cache: cache,
        );

        expect(
          await resolver.resolve('username@example.com'),
          isA<Nip05Found>(),
        );
      },
    );

    test('caches every identifier of a pubkey', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson({
          'names': {'alice': pubkey, 'bob': pubkey},
        }),
      );

      for (final identifier in [
        'alice@example.com',
        'bob@example.com',
        'alice@example.com',
        'bob@example.com',
      ]) {
        expect(await resolver.resolve(identifier), isA<Nip05Found>());
      }

      expect(requests, hasLength(2));
    });

    test('does not remember a Nip05ResolveError', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => http.Response('', 500),
      );

      await resolver.resolve('username@example.com');
      await resolver.resolve('username@example.com');

      expect(requests, hasLength(2));
    });

    test('lets an error of the cache through', () async {
      final saving = Nip05Resolver(
        cache: _FailingCache(),
        httpClient: MockClient((_) async => nostrJson(usernameJson)),
      );
      final loading = Nip05Resolver(
        cache: _FailingCache(failLoad: true),
        httpClient: MockClient((_) async => nostrJson(usernameJson)),
      );

      await expectLater(
        saving.resolve('username@example.com'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        loading.resolve('username@example.com'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('concurrent calls', () {
    test('share one request for one identifier', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
      );

      final results = await Future.wait([
        resolver.resolve('username@example.com'),
        resolver.resolve('UserName@example.com'),
        resolver.check(nip05: 'username@example.com', pubkey: pubkey),
      ]);

      expect(requests, hasLength(1));
      expect(results[0], isA<Nip05Found>());
      expect(results[1], isA<Nip05Found>());
      expect(results[2], isA<Nip05Verified>());
    });

    test('send one request per identifier', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
      );

      await Future.wait([
        resolver.resolve('username@example.com'),
        resolver.resolve('somethingDifferent@example.com'),
      ]);

      expect(requests, hasLength(2));
    });
  });

  group('check', () {
    test(
      'returns Nip05Verified when the identifier points to the pubkey',
      () async {
        final (:resolver, cache: _, requests: _) = setup(
          (_) => nostrJson(usernameJson),
        );

        final result = await resolver.check(
          nip05: 'username@example.com',
          pubkey: pubkey.toUpperCase(),
        );

        final data = (result as Nip05Verified).data;
        expect(data.pubkey, pubkey);
        expect(data.relays, ['wss://relay1.test', 'wss://relay2.test']);
      },
    );

    test('verifies the root identifier', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson(rootJson),
      );

      expect(
        await resolver.check(nip05: '_@domain.test', pubkey: pubkey),
        isA<Nip05Verified>(),
      );
    });

    test('returns Nip05Mismatch with what the identifier points to', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson(usernameJson),
      );

      final result = await resolver.check(
        nip05: 'username@example.com',
        pubkey: otherPubkey,
      );

      expect((result as Nip05Mismatch).data.pubkey, pubkey);
    });

    test('throws an ArgumentError for a pubkey that is not in hex, without a '
        'request', () async {
      final (:resolver, cache: _, :requests) = setup(
        (_) => nostrJson(usernameJson),
      );

      for (final other in [
        'npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6',
        '',
        '${pubkey}00',
      ]) {
        await expectLater(
          resolver.check(nip05: 'username@example.com', pubkey: other),
          throwsArgumentError,
          reason: other,
        );
      }
      expect(requests, isEmpty);
    });

    test(
      'returns Nip05NotFound for a missing or malformed identifier',
      () async {
        final (:resolver, cache: _, requests: _) = setup(
          (_) => nostrJson(rootJson),
        );

        for (final nip05 in ['domain@domain.test', '']) {
          expect(
            await resolver.check(nip05: nip05, pubkey: pubkey),
            isA<Nip05NotFound>(),
            reason: nip05,
          );
        }
      },
    );

    test('returns the Nip05ResolveError that kept it from checking', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => http.Response('', 500),
      );

      expect(
        await resolver.check(nip05: 'username@example.com', pubkey: pubkey),
        isA<Nip05ResolveNetworkError>(),
      );
    });

    test('leaves what resolve() gives as it was', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson(usernameJson),
      );

      await resolver.check(nip05: 'username@example.com', pubkey: otherPubkey);
      final result = await resolver.resolve('username@example.com');

      expect((result as Nip05Found).data.pubkey, pubkey);
    });

    test('does not reuse a cached result for another identifier', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (request) => request.url.queryParameters['name'] == 'username'
            ? nostrJson(usernameJson)
            : nostrJson({'names': {}}),
      );

      final previous = await resolver.check(
        nip05: 'username@example.com',
        pubkey: pubkey,
      );
      final switched = await resolver.check(
        nip05: 'jack@example.com',
        pubkey: pubkey,
      );

      expect(previous, isA<Nip05Verified>());
      expect(switched, isA<Nip05NotFound>());
    });

    test('concurrent calls for different pubkeys are not merged', () async {
      final (:resolver, cache: _, requests: _) = setup(
        (_) => nostrJson(usernameJson),
      );

      final results = await Future.wait([
        resolver.check(nip05: 'username@example.com', pubkey: pubkey),
        resolver.check(nip05: 'username@example.com', pubkey: otherPubkey),
      ]);

      expect(results[0], isA<Nip05Verified>());
      expect(results[1], isA<Nip05Mismatch>());
    });
  });

  group('abort', () {
    test('gives up on a server that never answers', () async {
      final client = _GatedClient();
      final resolver = Nip05Resolver(
        nip05Repository: HttpNip05Repository(
          client: client,
          timeout: const Duration(milliseconds: 50),
        ),
      );

      final resolved = await resolver.resolve('username@example.com');
      final checked = await resolver.check(
        nip05: 'username@example.com',
        pubkey: pubkey,
      );

      expect((resolved as Nip05ResolveError).cause, isA<TimeoutException>());
      expect(checked, isA<Nip05ResolveNetworkError>());
      expect(client.aborted, 2);
    });

    test(
      'an abortTrigger ends its call and the request it was alone on',
      () async {
        final client = _GatedClient();
        final resolver = Nip05Resolver(httpClient: client);
        final cancel = Completer<void>();

        final resolving = resolver.resolve(
          'username@example.com',
          abortTrigger: cancel.future,
        );
        await pumpEventQueue();
        cancel.complete();

        await expectLater(
          resolving,
          throwsA(isA<http.RequestAbortedException>()),
        );
        await pumpEventQueue();
        expect(client.aborted, 1);
      },
    );

    test('an abortTrigger that completes with an error aborts too', () async {
      final client = _GatedClient();
      final resolver = Nip05Resolver(httpClient: client);
      final cancel = Completer<void>();

      final checking = resolver.check(
        nip05: 'username@example.com',
        pubkey: pubkey,
        abortTrigger: cancel.future,
      );
      await pumpEventQueue();
      cancel.completeError(StateError('screen closed'));

      await expectLater(checking, throwsA(isA<http.RequestAbortedException>()));
    });

    test('the other calls on the request go on', () async {
      final client = _GatedClient();
      final resolver = Nip05Resolver(httpClient: client);
      final cancel = Completer<void>();

      final aborted = resolver.resolve(
        'username@example.com',
        abortTrigger: cancel.future,
      );
      final kept = resolver.resolve('username@example.com');
      await pumpEventQueue();
      cancel.complete();
      await expectLater(aborted, throwsA(isA<http.RequestAbortedException>()));
      client.release.complete();

      expect(await kept, isA<Nip05Found>());
      expect(client.sent, 1);
      expect(client.aborted, 0);
    });

    test(
      'an abortTrigger that fires while the cache is read sends nothing',
      () async {
        final cache = _GatedCache(blocked: 'username@example.com');
        final client = _GatedClient();
        final resolver = Nip05Resolver(cache: cache, httpClient: client);
        final cancel = Completer<void>();

        final resolving = resolver.resolve(
          'username@example.com',
          abortTrigger: cancel.future,
        );
        cancel.complete();
        await pumpEventQueue();
        cache.release.complete();

        await expectLater(
          resolving,
          throwsA(isA<http.RequestAbortedException>()),
        );
        expect(client.sent, 0);
      },
    );

    test(
      'abortPending() ends every call, and the resolver stays usable',
      () async {
        final cache = _GatedCache(blocked: 'alice@example.com');
        final client = _GatedClient();
        final resolver = Nip05Resolver(cache: cache, httpClient: client);

        final calls = [
          resolver.resolve('alice@example.com'),
          resolver.resolve('username@example.com'),
          resolver.resolve('username@example.com'),
        ];
        await pumpEventQueue();
        resolver.abortPending();
        final aborted = Future.wait([
          for (final call in calls)
            expectLater(call, throwsA(isA<http.RequestAbortedException>())),
        ]);
        cache.release.complete();
        await aborted;
        await pumpEventQueue();
        expect(client.sent, 1);
        expect(client.aborted, 1);

        client.release.complete();
        expect(
          await resolver.resolve('username@example.com'),
          isA<Nip05Found>(),
        );
      },
    );

    test(
      'close() ends the calls in flight and leaves a given client open',
      () async {
        final client = _GatedClient();
        final resolver = Nip05Resolver(httpClient: client);

        final resolving = resolver.resolve('username@example.com');
        await pumpEventQueue();
        resolver.close();

        await expectLater(
          resolving,
          throwsA(isA<http.RequestAbortedException>()),
        );
        expect(client.closed, isFalse);
      },
    );

    test('resolve() and check() throw a StateError after close()', () async {
      for (final resolver in [
        Nip05Resolver(),
        Nip05Resolver(httpClient: _GatedClient()),
      ]) {
        resolver.close();

        await expectLater(
          resolver.resolve('username@example.com'),
          throwsStateError,
        );
        await expectLater(
          resolver.check(nip05: 'username@example.com', pubkey: pubkey),
          throwsStateError,
        );
      }
    });
  });

  test('takes an httpClient or a nip05Repository, not both', () {
    final client = MockClient((_) async => http.Response('', 404));

    expect(
      () => Nip05Resolver(
        httpClient: client,
        nip05Repository: HttpNip05Repository(client: client),
      ),
      throwsArgumentError,
    );
  });
}

/// Answers with [usernameJson] once [release] completes, unless the request
/// is aborted first
class _GatedClient extends http.BaseClient {
  final release = Completer<void>();
  int sent = 0;
  int aborted = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent++;
    final abortTrigger = (request as http.Abortable).abortTrigger!;
    final wasAborted = await Future.any([
      release.future.then((_) => false),
      abortTrigger.then((_) => true),
    ]);
    if (wasAborted) {
      aborted++;
      throw http.RequestAbortedException(request.url);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(usernameJson))),
      200,
    );
  }

  @override
  void close() => closed = true;
}

/// Holds nothing, and reads [blocked] only once [release] completes
class _GatedCache implements Nip05Cache {
  final String blocked;
  final release = Completer<void>();

  _GatedCache({required this.blocked});

  @override
  Future<Nip05Record?> loadNip05(String identifier) async {
    if (identifier == blocked) await release.future;
    return null;
  }

  @override
  Future<void> saveNip05(Nip05Record record) async {}
}

/// Fails every save, and every load too when [failLoad]
class _FailingCache implements Nip05Cache {
  final bool failLoad;

  _FailingCache({this.failLoad = false});

  @override
  Future<Nip05Record?> loadNip05(String identifier) async {
    if (failLoad) throw StateError('cannot read');
    return null;
  }

  @override
  Future<void> saveNip05(Nip05Record record) async {
    throw StateError('disk full');
  }
}
