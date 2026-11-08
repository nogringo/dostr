import 'dart:async';

import 'package:ndk/ndk.dart' show Connectivy, RelayManager;
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
    final connectivity = Connectivy(
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

  test('an unreachable relay gives null and is asked again', () async {
    const url = 'wss://relay.example';
    final repo = _Repo();
    final connectivity = Connectivy(
      RelayManager(nostrTransportFactory: _NoTransport()),
      repo,
    );

    repo.next.completeError(TimeoutException(url));
    expect(await connectivity.getRelayInfo(url), isNull);
    expect(await connectivity.getRelayInfo(url), isNull);
    expect(repo.requested, [url, url]);
  });
}
