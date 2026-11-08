import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk_drift/ndk_drift.dart';

void main() {
  test('v12 -> v13 adds relay_infos', () async {
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
          db.execute('DROP TABLE relay_infos');
          db.execute('PRAGMA user_version = 12;');
        },
      ),
    );
    final cacheManager = DriftCacheManager(db);
    final record = RelayInfoRecord(
      url: 'wss://relay.example',
      info: RelayInfo(name: 'Example'),
      fetchedAt: DateTime.utc(2026),
    );

    await cacheManager.saveRelayInfo(record);

    expect(await cacheManager.loadRelayInfo(record.url), record);
    await db.close();
  });
}
