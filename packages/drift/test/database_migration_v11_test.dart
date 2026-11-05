import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_drift/ndk_drift.dart';

void main() {
  test('v10 -> v11 moves sources_json to the event provenance', () async {
    final event = Nip01Event(
      pubKey: 'a' * 64,
      kind: 1,
      tags: [],
      content: 'hello',
      createdAt: 100,
    );
    final malformed = Nip01Event(
      pubKey: 'a' * 64,
      kind: 1,
      tags: [],
      content: 'malformed sources',
      createdAt: 100,
    );

    final db = NdkCacheDatabase.forTesting(
      NativeDatabase.memory(
        setup: (db) {
          db.execute('''
            CREATE TABLE events (
              id TEXT NOT NULL PRIMARY KEY,
              pub_key TEXT NOT NULL,
              kind INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              content TEXT NOT NULL,
              sig TEXT,
              valid_sig INTEGER,
              tags_json TEXT NOT NULL,
              sources_json TEXT NOT NULL
            );
          ''');
          db.execute('''
            CREATE TABLE event_sources_table (
              event_id TEXT NOT NULL,
              relay_url TEXT NOT NULL,
              PRIMARY KEY (event_id, relay_url)
            );
          ''');
          db.execute(
            "INSERT INTO events VALUES (?, ?, 1, 100, ?, NULL, NULL, '[]', ?)",
            [
              event.id,
              event.pubKey,
              event.content,
              '["wss://a.example","wss://b.example"]',
            ],
          );
          db.execute(
            "INSERT INTO events VALUES (?, ?, 1, 100, ?, NULL, NULL, '[]', ?)",
            [malformed.id, malformed.pubKey, malformed.content, 'not json'],
          );
          db.execute('INSERT INTO event_sources_table VALUES (?, ?)', [
            event.id,
            'wss://a.example',
          ]);
          // DriftCacheManager touches them on construction
          db.execute('''
            CREATE TABLE wallets (
              id TEXT NOT NULL PRIMARY KEY,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              supported_units_json TEXT NOT NULL,
              metadata_json TEXT NOT NULL
            );
          ''');
          db.execute('''
            CREATE TABLE key_values (
              key TEXT NOT NULL PRIMARY KEY,
              value TEXT
            );
          ''');
          db.execute('PRAGMA user_version = 9;');
        },
      ),
    );
    final cacheManager = DriftCacheManager(db);

    expect(
      (await cacheManager.loadEvents(ids: [event.id, malformed.id])).length,
      2,
    );
    expect(
      await cacheManager.loadEventSources(event.id),
      unorderedEquals(['wss://a.example', 'wss://b.example']),
    );
    expect(await cacheManager.loadEventSources(malformed.id), isEmpty);
    final columns = await db
        .customSelect("SELECT name FROM pragma_table_info('events')")
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      isNot(contains('sources_json')),
    );

    await db.close();
  });
}
