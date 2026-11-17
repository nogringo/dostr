import 'package:dostr_nip11/dostr_nip11.dart';
import 'package:test/test.dart';

class _Repo implements RelayInfoRepository {
  final Future<RelayInfo?> Function() answer;

  _Repo(this.answer);

  @override
  Future<RelayInfo?> getRelayInfo(String url) => answer();
}

void main() {
  const url = 'wss://relay.example';

  test('reads the limits the relay publishes', () async {
    final repo = _Repo(
      () async => RelayInfo(
        limitation: RelayLimitation(
          maxSubscriptions: 200,
          maxMessageLength: 65536,
        ),
      ),
    );

    expect(await repo.maxSubscriptions(url), 200);
    expect(await repo.maxMessageLength(url), 65536);
  });

  test('gives null for a relay without limits', () async {
    final repo = _Repo(() async => RelayInfo());

    expect(await repo.maxSubscriptions(url), isNull);
    expect(await repo.maxMessageLength(url), isNull);
  });

  test('gives null for a relay that could not be reached', () async {
    final repo = _Repo(() async => throw StateError('offline'));

    expect(await repo.maxSubscriptions(url), isNull);
    expect(await repo.maxMessageLength(url), isNull);
  });
}
