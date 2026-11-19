import 'package:clock/clock.dart';
import 'package:dostr_nip05/dostr_nip05.dart';
import 'package:dostr_nip05/src/memory_nip_05_cache.dart';
import 'package:test/test.dart';

final start = DateTime.utc(2026, 11, 19, 12);

/// saves a record of [identifier] fetched [after] [start], at that time
Future<void> saveAt(MemoryNip05Cache cache, String identifier, Duration after) {
  final at = start.add(after);
  return withClock(
    Clock.fixed(at),
    () => cache.saveNip05(Nip05Record(identifier: identifier, fetchedAt: at)),
  );
}

void main() {
  test('drops the records as old as maxAge when it saves one', () async {
    final cache = MemoryNip05Cache(maxAge: const Duration(hours: 1));

    await saveAt(cache, 'old@example.com', Duration.zero);
    await saveAt(cache, 'recent@example.com', const Duration(minutes: 1));
    await saveAt(cache, 'new@example.com', const Duration(hours: 1));

    expect(await cache.loadNip05('old@example.com'), isNull);
    expect(await cache.loadNip05('recent@example.com'), isNotNull);
    expect(await cache.loadNip05('new@example.com'), isNotNull);
  });

  test('ages a record from when it was last saved', () async {
    final cache = MemoryNip05Cache(maxAge: const Duration(hours: 1));

    await saveAt(cache, 'alice@example.com', Duration.zero);
    await saveAt(cache, 'bob@example.com', const Duration(minutes: 30));
    await saveAt(cache, 'alice@example.com', const Duration(minutes: 50));
    await saveAt(cache, 'carol@example.com', const Duration(minutes: 95));

    expect(await cache.loadNip05('bob@example.com'), isNull);
    expect(await cache.loadNip05('alice@example.com'), isNotNull);
  });
}
