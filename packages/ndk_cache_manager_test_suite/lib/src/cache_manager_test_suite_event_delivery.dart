part of 'cache_manager_test_suite.dart';

void _runEventDeliveryTests(CacheManager Function() getCacheManager) {
  test('keeps the unresolved url sets of a delivery record', () async {
    final cacheManager = getCacheManager();
    const record = EventDeliveryRecord(
      eventId: 'unresolved_event',
      createdAt: 10,
      updatedAt: 11,
      unresolvedUrlSets: [
        UnresolvedUrlSet(urlSet: UrlSet.first(5, UrlSet.inbox('bob'))),
        UnresolvedUrlSet(
          urlSet: UrlSet.fallback([
            UrlSet.outbox('alice'),
            UrlSet.explicit(['wss://relay.example']),
          ]),
          authCanonical: 'never',
        ),
      ],
    );

    await cacheManager.saveEventDeliveryRecord(record);
    final restored = await cacheManager.loadEventDeliveryRecord(record.eventId);

    expect(restored?.toJson(), record.toJson());
  });
}
