part of 'cache_manager_test_suite.dart';

void _runRelayInfoTests(CacheManager Function() getCacheManager) {
  const url = 'wss://relay-info.example';
  final fetchedAt = DateTime.utc(2026, 11, 8, 12, 30, 15, 123);

  test('saveRelayInfo and loadRelayInfo', () async {
    final cacheManager = getCacheManager();
    final record = RelayInfoRecord(
      url: url,
      info: RelayInfo.fromJson({
        'name': 'Example',
        'supported_nips': [1, 11, '7D'],
        'limitation': {'max_subscriptions': 200, 'max_filters': 10},
        'fees': {
          'admission': [
            {'amount': 1000, 'unit': 'msats'},
          ],
        },
        'retention': [
          {
            'kinds': [0, 3],
            'time': null,
          },
        ],
      }),
      fetchedAt: fetchedAt,
    );

    await cacheManager.saveRelayInfo(record);

    expect(await cacheManager.loadRelayInfo(url), equals(record));
  });

  test('saveRelayInfo stores a relay without document', () async {
    final cacheManager = getCacheManager();
    final record = RelayInfoRecord(url: url, fetchedAt: fetchedAt);

    await cacheManager.saveRelayInfo(record);
    final loaded = await cacheManager.loadRelayInfo(url);

    expect(loaded, equals(record));
    expect(loaded!.info, isNull);
  });

  test('saveRelayInfo replaces the record of its url', () async {
    final cacheManager = getCacheManager();
    final updated = RelayInfoRecord(
      url: url,
      info: RelayInfo(name: 'Updated'),
      fetchedAt: fetchedAt.add(const Duration(hours: 1)),
    );

    await cacheManager.saveRelayInfo(
      RelayInfoRecord(
        url: url,
        info: RelayInfo(name: 'First'),
        fetchedAt: fetchedAt,
      ),
    );
    await cacheManager.saveRelayInfo(updated);

    expect(await cacheManager.loadRelayInfo(url), equals(updated));
  });

  test('loadRelayInfo returns null for an unknown url', () async {
    final cacheManager = getCacheManager();

    expect(await cacheManager.loadRelayInfo('wss://unknown.example'), isNull);
  });

  test('urls are keys as given, case included', () async {
    final cacheManager = getCacheManager();
    final upper = RelayInfoRecord(
      url: 'wss://Relay-Info.example',
      info: RelayInfo(name: 'Upper'),
      fetchedAt: fetchedAt,
    );
    final lower = RelayInfoRecord(
      url: url,
      info: RelayInfo(name: 'Lower'),
      fetchedAt: fetchedAt,
    );

    await cacheManager.saveRelayInfo(upper);
    await cacheManager.saveRelayInfo(lower);

    expect(await cacheManager.loadRelayInfo(upper.url), equals(upper));
    expect(await cacheManager.loadRelayInfo(lower.url), equals(lower));
  });

  test('removeRelayInfo removes one url only', () async {
    final cacheManager = getCacheManager();
    final other = RelayInfoRecord(
      url: 'wss://other-relay-info.example',
      fetchedAt: fetchedAt,
    );

    await cacheManager.saveRelayInfo(
      RelayInfoRecord(url: url, fetchedAt: fetchedAt),
    );
    await cacheManager.saveRelayInfo(other);
    await cacheManager.removeRelayInfo(url);

    expect(await cacheManager.loadRelayInfo(url), isNull);
    expect(await cacheManager.loadRelayInfo(other.url), equals(other));
  });

  test('removeAllRelayInfos removes every url', () async {
    final cacheManager = getCacheManager();
    const other = 'wss://other-relay-info.example';

    await cacheManager.saveRelayInfo(
      RelayInfoRecord(url: url, fetchedAt: fetchedAt),
    );
    await cacheManager.saveRelayInfo(
      RelayInfoRecord(url: other, fetchedAt: fetchedAt),
    );
    await cacheManager.removeAllRelayInfos();

    expect(await cacheManager.loadRelayInfo(url), isNull);
    expect(await cacheManager.loadRelayInfo(other), isNull);
  });
}
