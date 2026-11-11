part of 'cache_manager_test_suite.dart';

void _runLearnedMessageLengthTests(CacheManager Function() getCacheManager) {
  const url = 'wss://learned-message-length.example';
  const other = 'wss://other-learned-message-length.example';

  test('saveLearnedMessageLength and loadLearnedMessageLength', () async {
    final cacheManager = getCacheManager();

    await cacheManager.saveLearnedMessageLength(url, 65535);

    expect(await cacheManager.loadLearnedMessageLength(url), 65535);
  });

  test('saveLearnedMessageLength replaces the length of its url', () async {
    final cacheManager = getCacheManager();

    await cacheManager.saveLearnedMessageLength(url, 131071);
    await cacheManager.saveLearnedMessageLength(url, 65535);

    expect(await cacheManager.loadLearnedMessageLength(url), 65535);
  });

  test('loadLearnedMessageLength returns null for an unknown url', () async {
    final cacheManager = getCacheManager();

    expect(
      await cacheManager.loadLearnedMessageLength('wss://unknown.example'),
      isNull,
    );
  });

  test('urls are keys as given, case included', () async {
    final cacheManager = getCacheManager();
    const upper = 'wss://Learned-Message-Length.example';

    await cacheManager.saveLearnedMessageLength(upper, 1000);
    await cacheManager.saveLearnedMessageLength(url, 2000);

    expect(await cacheManager.loadLearnedMessageLength(upper), 1000);
    expect(await cacheManager.loadLearnedMessageLength(url), 2000);
  });

  test('removeLearnedMessageLength removes one url only', () async {
    final cacheManager = getCacheManager();

    await cacheManager.saveLearnedMessageLength(url, 1000);
    await cacheManager.saveLearnedMessageLength(other, 2000);
    await cacheManager.removeLearnedMessageLength(url);

    expect(await cacheManager.loadLearnedMessageLength(url), isNull);
    expect(await cacheManager.loadLearnedMessageLength(other), 2000);
  });

  test('removeAllLearnedMessageLengths removes every url', () async {
    final cacheManager = getCacheManager();

    await cacheManager.saveLearnedMessageLength(url, 1000);
    await cacheManager.saveLearnedMessageLength(other, 2000);
    await cacheManager.removeAllLearnedMessageLengths();

    expect(await cacheManager.loadLearnedMessageLength(url), isNull);
    expect(await cacheManager.loadLearnedMessageLength(other), isNull);
  });
}
