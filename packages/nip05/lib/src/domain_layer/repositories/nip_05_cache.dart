import '../entities/nip_05_record.dart';

/// Where [Nip05Resolver] keeps what it resolved, keyed by
/// [Nip05Record.identifier].
abstract interface class Nip05Cache {
  /// replaces the record of its identifier
  Future<void> saveNip05(Nip05Record record);

  Future<Nip05Record?> loadNip05(String identifier);
}
