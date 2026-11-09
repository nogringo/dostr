import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ndk_drift/ndk_drift.dart';

void main() {
  test('v13 -> v14 adds learned_message_lengths', () async {
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
          db.execute('DROP TABLE learned_message_lengths');
          db.execute('PRAGMA user_version = 13;');
        },
      ),
    );
    final cacheManager = DriftCacheManager(db);

    await cacheManager.saveLearnedMessageLength('wss://relay.example', 65535);

    expect(
      await cacheManager.loadLearnedMessageLength('wss://relay.example'),
      65535,
    );
    await db.close();
  });
}
