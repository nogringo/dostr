import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk/ndk.dart' show Connectivity, MemCacheManager, RelayManager;
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nip11/ndk_nip11.dart';
import 'package:ndk_core/domain_layer/repositories/nostr_transport.dart';
import 'package:test/test.dart';

class _Repo implements RelayInfoRepo {
  final requested = <String>[];
  final next = Completer<RelayInfo?>();

  @override
  Future<RelayInfo?> getRelayInfo(String url) {
    requested.add(url);
    return next.future;
  }
}

class _NoTransport implements NostrTransportFactory {
  @override
  NostrTransport call(String url) => throw UnimplementedError();
}

void main() {
  test('spellings of one relay url share one fetch', () async {
    const url = 'wss://relay.example';
    final info = RelayInfo.fromJson({'name': 'Example'});
    final repo = _Repo();
    final connectivity = Connectivity(
      RelayManager(nostrTransportFactory: _NoTransport()),
      repo,
    );

    final first = connectivity.getRelayInfo(url);
    final second = connectivity.getRelayInfo('$url/');
    repo.next.complete(info);

    expect(await first, same(info));
    expect(await second, same(info));
    expect(await connectivity.getRelayInfo(url), same(info));
    expect(repo.requested, [url]);
  });

  test('an unreachable relay gives null and is asked again later', () async {
    const url = 'wss://relay.example';
    final repo = _Repo();
    final connectivity = Connectivity(
      RelayManager(nostrTransportFactory: _NoTransport()),
      repo,
    );

    repo.next.completeError(TimeoutException(url));
    expect(await connectivity.getRelayInfo(url), isNull);
    expect(await connectivity.getRelayInfo(url), isNull);
    expect(repo.requested, [url]);
  });

  test('a url that is not a relay url gives null', () async {
    final relay = MockClient((_) async => http.Response('{}', 200));
    final connectivity = Connectivity(
      RelayManager(nostrTransportFactory: _NoTransport()),
      HttpRelayInfoRepo(NdkHttp(relay)),
    );

    expect(await connectivity.getRelayInfo('relay.example'), isNull);
  });

  test('a restart on the same cache reads the document from it', () async {
    const url = 'wss://relay.example';
    final info = RelayInfo.fromJson({'name': 'Example'});
    final cache = MemCacheManager();
    final repo = _Repo();
    Connectivity restart() => Connectivity(
      RelayManager(nostrTransportFactory: _NoTransport()),
      repo,
      cache: cache,
    );

    repo.next.complete(info);
    expect(await restart().getRelayInfo(url), info);
    expect(await restart().getRelayInfo('$url/'), info);
    expect(repo.requested, [url]);
  });
}
