import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk/presentation_layer/cache_manager_replaceable_events.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:test/test.dart';

void main() {
  const pubKey =
      '76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa';

  Nip01Event event({required int kind, required int createdAt, String? dTag}) =>
      Nip01Event(
        pubKey: pubKey,
        kind: kind,
        tags: [
          if (dTag != null) ['d', dTag],
        ],
        content: '',
        createdAt: createdAt,
      );

  late MemCacheManager cacheManager;
  late CacheManagerReplaceableEvents events;

  setUp(() {
    cacheManager = MemCacheManager();
    events = CacheManagerReplaceableEvents(cacheManager);
  });

  test('saves into the cache manager and loads the newest', () async {
    await events.save(event(kind: 10002, createdAt: 1));
    final newest = event(kind: 10002, createdAt: 2);
    await events.save(newest);

    expect(await events.load(kind: 10002, pubKey: pubKey), newest);
    expect(await cacheManager.loadEvent(newest.id), newest);
  });

  test('loads an addressable event by its d tag', () async {
    final servers = event(kind: 30002, createdAt: 1, dTag: 'servers');
    await events.save(servers);
    await events.save(event(kind: 30002, createdAt: 2, dTag: 'other'));

    expect(
      await events.load(kind: 30002, pubKey: pubKey, dTag: 'servers'),
      servers,
    );
  });

  test('loads null when nothing matches', () async {
    await events.save(event(kind: 10002, createdAt: 1));

    expect(await events.load(kind: 10050, pubKey: pubKey), isNull);
  });
}
