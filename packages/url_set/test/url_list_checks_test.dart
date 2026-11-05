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
}
