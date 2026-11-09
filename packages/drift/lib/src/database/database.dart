import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:ndk_cache/ndk_cache.dart' show EventCacheStateRecord;
import 'package:ndk_follows/ndk_follows.dart' show ContactList;
import 'package:ndk_metadatas/ndk_metadatas.dart' show Metadata;
import 'package:ndk_nip01/ndk_nip01.dart' show Nip01Event;
import 'package:path_provider/path_provider.dart';

import 'event_index.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Events,
    EventTags,
    DeletionTargets,
    UserRelayLists,
    RelaySets,
    Nip05s,
    RelayInfos,
    LearnedMessageLengths,
    FilterFetchedRangeRecords,
    EventSourcesTable,
    EventDeliveryRecordsTable,
    RelayDeliveryTargetsTable,
    // Cashu tables
    CashuProofs,
    CashuKeysets,
    CashuMintInfos,
    CashuSecretCounters,
    KeyValues,
    Wallets,
    WalletTransactions,
  ],
)
class NdkCacheDatabase extends _$NdkCacheDatabase {
  NdkCacheDatabase({String? dbName})
    : super(
        _openConnection(
          dbName ?? (kDebugMode ? 'ndk_cache_debug' : 'ndk_cache'),
        ),
      );

  NdkCacheDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 3) {
          // Add Cashu tables
          await m.createTable(cashuProofs);
          await m.createTable(cashuKeysets);
          await m.createTable(cashuMintInfos);
          await m.createTable(cashuSecretCounters);
          await m.createTable(wallets);
          await m.createTable(walletTransactions);
        }
        if (from < 4) {
          // Add key-value table for settings
          await m.createTable(keyValues);
        }
        if (from < 5) {
          // Add event source provenance and delivery tracking tables
          await m.createTable(eventSourcesTable);
          await m.createTable(eventDeliveryRecordsTable);
          await m.createTable(relayDeliveryTargetsTable);
        }
        if (from < 6) {
          // Metadata and contact-list projections are derived from generic
          // events now. Copy legacy rows into the events table so cached
          // profiles and follow lists survive the upgrade, then drop the
          // legacy tables.
          await _migrateLegacyMetadatas();
          await _migrateLegacyContactLists();
        }
        // which identity an event goes to a relay under, see AuthPolicy. Only
        // for a database that already had the table: createTable above builds
        // it from today's definition, column included, so adding it again
        // there would fail on a duplicate
        if (from >= 5 && from < 7) {
          await m.addColumn(
            relayDeliveryTargetsTable,
            relayDeliveryTargetsTable.authCanonical,
          );
        }
        if (from < 8) {
          await m.createIndex(eventsPubKeyKindCreatedAt);
          await m.createIndex(eventsKindCreatedAt);
        }
        // keyed by identifier since #936, the cached rows are dropped
        if (from < 9) {
          await m.deleteTable('nip05s');
          await m.createTable(nip05s);
        }
        if (from < 10) {
          await transaction(() async {
            await m.addColumn(events, events.conflictKey);
            await m.addColumn(events, events.expiration);
            await m.createTable(eventTags);
            await m.createTable(deletionTargets);
            for (final index in [
              eventsCreatedAt,
              eventsConflictKey,
              eventsExpiration,
              eventTagsNameValue,
              eventTagsEventId,
              deletionTargetsEventId,
              deletionTargetsConflictKey,
              deletionTargetsDeletionId,
            ]) {
              await m.createIndex(index);
            }
            await _backfillEventIndex();
          });
        }
        if (from < 11) {
          await transaction(() async {
            await _moveEventSourcesToProvenance();
            await m.dropColumn(events, 'sources_json');
          });
        }
        // Nip01Event.validSig is gone, nothing read it
        if (from < 12) {
          await m.dropColumn(events, 'valid_sig');
        }
        if (from < 13) {
          await m.createTable(relayInfos);
        }
        if (from < 14) {
          await m.createTable(learnedMessageLengths);
        }
      },
      // event_tags and deletion_targets follow their event through ON DELETE
      // CASCADE
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Derives the visibility state of the events stored before v10.
  Future<void> _backfillEventIndex() async {
    var after = '';
    while (true) {
      final rows = await customSelect(
        'SELECT id, pub_key, kind, created_at, tags_json FROM events '
        'WHERE id > ? ORDER BY id LIMIT 500',
        variables: [Variable.withString(after)],
      ).get();
      if (rows.isEmpty) return;
      await batch((batch) {
        for (final row in rows) {
          final event = Nip01Event(
            id: row.read<String>('id'),
            pubKey: row.read<String>('pub_key'),
            kind: row.read<int>('kind'),
            createdAt: row.read<int>('created_at'),
            tags: _decodeTagList(row.read<String>('tags_json')),
            content: '',
          );
          batch.update(
            events,
            EventsCompanion(
              conflictKey: Value(EventCacheStateRecord.conflictKeyFor(event)),
              expiration: Value(eventExpiration(event)),
            ),
            where: (t) => t.id.equals(event.id),
          );
          insertEventIndex(batch, this, event);
        }
      });
      after = rows.last.read<String>('id');
    }
  }

  /// Copies the relays of the pre-v11 `sources_json` column into
  /// `event_sources_table`, which holds the provenance since v5.
  Future<void> _moveEventSourcesToProvenance() async {
    await customStatement(
      'INSERT OR IGNORE INTO event_sources_table (event_id, relay_url) '
      'SELECT events.id, source.value FROM events, json_each('
      "CASE WHEN json_valid(events.sources_json) THEN events.sources_json "
      "ELSE '[]' END) AS source "
      "WHERE source.type = 'text'",
    );
  }

  /// Copies rows of the pre-v6 `metadatas` table into the events table as
  /// projected kind-0 events (unsigned, `sig` stays null).
  Future<void> _migrateLegacyMetadatas() async {
    if (!await _legacyTableExists('metadatas')) return;
    final rows = await customSelect('SELECT * FROM metadatas').get();
    for (final row in rows) {
      final updatedAt = row.readNullable<int>('updated_at');
      // Without the original created_at the event cannot be ordered against
      // relay data, so such rows are dropped.
      if (updatedAt == null || updatedAt <= 0) continue;
      var content = row.readNullable<String>('raw_content_json');
      if (content == null || content.isEmpty) {
        final json = <String, dynamic>{};
        for (final field in const [
          'name',
          'display_name',
          'picture',
          'banner',
          'website',
          'about',
          'nip05',
          'lud16',
          'lud06',
        ]) {
          final value = row.readNullable<String>(field);
          if (value != null) json[field] = value;
        }
        content = jsonEncode(json);
      }
      await _insertProjectedEvent(
        Nip01Event(
          pubKey: row.read<String>('pub_key'),
          kind: Metadata.kKind,
          tags: _decodeTagList(row.readNullable<String>('tags_json')),
          content: content,
          createdAt: updatedAt,
        ),
        sources: _decodeStringList(row.readNullable<String>('sources_json')),
      );
    }
    await customStatement('DROP TABLE metadatas');
  }

  /// Copies rows of the pre-v6 `contact_lists` table into the events table as
  /// projected kind-3 events (unsigned, `sig` stays null).
  Future<void> _migrateLegacyContactLists() async {
    if (!await _legacyTableExists('contact_lists')) return;
    final rows = await customSelect('SELECT * FROM contact_lists').get();
    for (final row in rows) {
      final createdAt = row.read<int>('created_at');
      if (createdAt <= 0) continue;
      final contactList =
          ContactList(
              pubKey: row.read<String>('pub_key'),
              contacts: _decodeStringList(
                row.readNullable<String>('contacts_json'),
              ),
            )
            ..contactRelays = _decodeStringList(
              row.readNullable<String>('contact_relays_json'),
            )
            ..petnames = _decodeStringList(
              row.readNullable<String>('petnames_json'),
            )
            ..followedTags = _decodeStringList(
              row.readNullable<String>('followed_tags_json'),
            )
            ..followedCommunities = _decodeStringList(
              row.readNullable<String>('followed_communities_json'),
            )
            ..followedEvents = _decodeStringList(
              row.readNullable<String>('followed_events_json'),
            )
            ..createdAt = createdAt;
      await _insertProjectedEvent(
        contactList.toEvent(),
        sources: _decodeStringList(row.readNullable<String>('sources_json')),
      );
    }
    await customStatement('DROP TABLE contact_lists');
  }

  Future<bool> _legacyTableExists(String name) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Raw SQL because the events table still has its pre-v11 `sources_json`
  /// column at this step, which the v11 step then moves to the provenance.
  Future<void> _insertProjectedEvent(
    Nip01Event event, {
    required List<String> sources,
  }) async {
    await customStatement(
      'INSERT OR IGNORE INTO events (id, pub_key, kind, created_at, content, '
      'sig, valid_sig, tags_json, sources_json) '
      'VALUES (?, ?, ?, ?, ?, NULL, NULL, ?, ?)',
      [
        event.id,
        event.pubKey,
        event.kind,
        event.createdAt,
        event.content,
        jsonEncode(event.tags),
        jsonEncode(sources),
      ],
    );
  }

  List<String> _decodeStringList(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(json) as List);
    } catch (_) {
      return [];
    }
  }

  List<List<String>> _decodeTagList(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List)
          .map((tag) => List<String>.from(tag as List))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static QueryExecutor _openConnection(String dbName) {
    return driftDatabase(
      name: dbName,
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }
}
