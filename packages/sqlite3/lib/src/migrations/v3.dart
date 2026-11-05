// Nip01Event.sources is gone: the relays of events.sources move to
// event_sources, the provenance since v1.
const v3 = '''
INSERT OR IGNORE INTO event_sources (event_id, relay_url)
  SELECT events.id, source.value FROM events, json_each(
    CASE WHEN json_valid(events.sources) THEN events.sources ELSE '[]' END
  ) AS source
  WHERE source.type = 'text';
ALTER TABLE events DROP COLUMN sources;
''';
