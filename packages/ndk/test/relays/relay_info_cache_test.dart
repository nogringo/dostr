import 'dart:async';

import 'package:ndk/domain_layer/entities/relay_info.dart';
import 'package:ndk/domain_layer/repositories/relay_info_repo.dart';
import 'package:ndk/domain_layer/usecases/connectivity/connectivity.dart';
import 'package:ndk_core/domain_layer/repositories/nostr_transport.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
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

class _NoTransport implements NostrTransportFactory {
  @override
  NostrTransport call(String url) => throw UnimplementedError();
}

void main() {
  const url = 'wss://relay.example';
  final info = RelayInfo.fromJson({'name': 'Example'});
  late _Repo repo;
  late Connectivy connectivity;

  setUp(() {
    repo = _Repo();
    connectivity = Connectivy(
      RelayManager(nostrTransportFactory: _NoTransport()),
      repo,
    );
  });

  test('concurrent and later calls share one fetch per relay', () async {
    final first = connectivity.getRelayInfo(url);
    final second = connectivity.getRelayInfo('$url/');
    repo.next.complete(info);

    expect(await first, same(info));
    expect(await second, same(info));
    expect(await connectivity.getRelayInfo(url), same(info));
    expect(repo.requested, [url]);
  });

  test('a failed fetch is retried on the next call', () async {
    repo.next.complete(null);
    expect(await connectivity.getRelayInfo(url), isNull);

    repo.next = Completer()..complete(info);
    expect(await connectivity.getRelayInfo(url), same(info));
    expect(repo.requested, [url, url]);
  });

  test('a throwing repo is retried on the next call', () async {
    repo.next.completeError(StateError('offline'));
    await expectLater(connectivity.getRelayInfo(url), throwsStateError);

    repo.next = Completer()..complete(info);
    expect(await connectivity.getRelayInfo(url), same(info));
  });
}
