import 'dart:convert';

import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:test/test.dart';

void main() {
  test('a check round-trips through its map', () {
    final check = UrlListCheck(
      pubkey: 'p',
      kind: 10002,
      checkedAt: DateTime.utc(2026, 10, 13, 12),
      found: true,
    );
    final read = UrlListCheck.fromMap(
      jsonDecode(jsonEncode(check.toMap())) as Map,
    );
    expect(read.toMap(), check.toMap());
    expect(read.checkedAt, check.checkedAt);
    expect(check.toMap().containsKey('dTag'), isFalse);
  });

  test('a check of an addressable list round-trips its d tag', () {
    final check = UrlListCheck(
      pubkey: 'p',
      kind: 36205,
      dTag: 'home-relays',
      checkedAt: DateTime.utc(2026, 10, 13, 12),
      found: true,
    );
    final read = UrlListCheck.fromMap(
      jsonDecode(jsonEncode(check.toMap())) as Map,
    );
    expect(read.dTag, 'home-relays');
    expect(read.toMap(), check.toMap());
  });

  test('the memory store keeps one check per pubkey and kind', () async {
    final store = MemoryUrlListCheckStore();
    UrlListCheck check(int kind, {required bool found}) => UrlListCheck(
      pubkey: 'p',
      kind: kind,
      checkedAt: DateTime.utc(2026),
      found: found,
    );

    await store.write(check(10002, found: false));
    await store.write(check(10002, found: true));
    await store.write(check(10050, found: false));

    expect((await store.read('p', 10002))?.found, isTrue);
    expect((await store.read('p', 10050))?.found, isFalse);
    expect(await store.read('q', 10002), isNull);
  });

  test('the memory store keeps one check per d tag', () async {
    final store = MemoryUrlListCheckStore();
    UrlListCheck check(String? dTag, {required bool found}) => UrlListCheck(
      pubkey: 'p',
      kind: 30000,
      dTag: dTag,
      checkedAt: DateTime.utc(2026),
      found: found,
    );

    await store.write(check('a', found: true));
    await store.write(check('b', found: false));

    expect((await store.read('p', 30000, dTag: 'a'))?.found, isTrue);
    expect((await store.read('p', 30000, dTag: 'b'))?.found, isFalse);
    expect(await store.read('p', 30000), isNull);
  });
}
