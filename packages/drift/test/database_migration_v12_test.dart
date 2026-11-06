import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_drift/ndk_drift.dart';

void main() {
  test('v11 -> v12 drops valid_sig', () async {
    final event = Nip01Event(
      pubKey: 'a' * 64,
      kind: 1,
      tags: [],
      content: 'hello',
      createdAt: 100,
    );
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/ndk.db');

    final current = NdkCacheDatabase.forTesting(NativeDatabase(file));
    await current.customSelect('SELECT 1').get();
    await current.close();

    final db = NdkCacheDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (db) {
          db.execute('ALTER TABLE events ADD COLUMN valid_sig INTEGER');
          db.execute(
            'INSERT INTO events (id, pub_key, kind, created_at, content, '
            "tags_json, valid_sig) VALUES (?, ?, 1, 100, ?, '[]', 1)",
            [event.id, event.pubKey, event.content],
          );
          db.execute('PRAGMA user_version = 11;');
        },
      ),
    );
    final cacheManager = DriftCacheManager(db);

    expect((await cacheManager.loadEvent(event.id))?.toJson(), event.toJson());
    final columns = await db
        .customSelect("SELECT name FROM pragma_table_info('events')")
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      isNot(contains('valid_sig')),
    );

    await db.close();
  });
}
