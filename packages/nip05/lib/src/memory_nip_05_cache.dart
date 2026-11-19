import 'package:clock/clock.dart';

import 'nip_05_cache.dart';
import 'nip_05_record.dart';

/// The cache of a `Nip05Resolver` given none, which drops the records as old
/// as [maxAge] whenever it saves one
class MemoryNip05Cache implements Nip05Cache {
  final Duration maxAge;

  // in the order they were last saved, so the oldest come first
  final Map<String, Nip05Record> _records = {};

  MemoryNip05Cache({required this.maxAge});

  @override
  Future<void> saveNip05(Nip05Record record) async {
    _records
      ..remove(record.identifier)
      ..[record.identifier] = record;
    final now = clock.now();
    while (_records.isNotEmpty &&
        now.difference(_records.values.first.fetchedAt) >= maxAge) {
      _records.remove(_records.keys.first);
    }
  }

  @override
  Future<Nip05Record?> loadNip05(String identifier) async =>
      _records[identifier];
}
