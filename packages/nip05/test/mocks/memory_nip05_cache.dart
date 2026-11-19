import 'package:dostr_nip05/dostr_nip05.dart';

class MemoryNip05Cache implements Nip05Cache {
  final Map<String, Nip05Record> records = {};

  @override
  Future<void> saveNip05(Nip05Record record) async {
    records[record.identifier] = record;
  }

  @override
  Future<Nip05Record?> loadNip05(String identifier) async =>
      records[identifier];
}
