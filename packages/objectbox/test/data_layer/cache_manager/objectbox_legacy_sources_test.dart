// Run explicitly with the matching ObjectBox native library, see
// objectbox_visibility_integration_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ndk_objectbox/data_layer/db/object_box/schema/db_nip_01_event.dart';
import 'package:ndk_objectbox/ndk_objectbox.dart';
import 'package:ndk_objectbox/objectbox.g.dart';

void main() {
  test(
    'opening moves the relays of legacySources to the provenance once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'objectbox-legacy-sources-',
      );
      addTearDown(() => directory.delete(recursive: true));

      final store = await openStore(directory: directory.path);
      store.box<DbNip01Event>().put(
        DbNip01Event(
            nostrId: 'event-1',
            pubKey: 'pubkey',
            kind: 1,
            content: '',
            createdAt: 1,
          )
          ..tags = []
          ..legacySources = ['wss://b.example', 'wss://a.example'],
      );
      store.close();

      var db = DbObjectBox(directory: directory.path);
      await db.dbRdy;
      expect(await db.loadEventSources('event-1'), [
        'wss://a.example',
        'wss://b.example',
      ]);

      await db.removeEventSources('event-1');
      await db.close();
      db = DbObjectBox(directory: directory.path);
      await db.dbRdy;
      expect(await db.loadEventSources('event-1'), isEmpty);
      await db.close();
    },
    skip: Platform.environment['RUN_OBJECTBOX_TESTS'] != '1'
        ? 'Set RUN_OBJECTBOX_TESTS=1 and provide matching ObjectBox native library.'
        : false,
  );
}
