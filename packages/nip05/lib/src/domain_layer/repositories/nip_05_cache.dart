import '../entities/nip_05.dart';

/// Where [Nip05Usecase] keeps the identifiers it resolved, keyed by
/// [Nip05.canonicalIdentifier].
abstract interface class Nip05Cache {
  Future<void> saveNip05(Nip05 nip05);

  Future<Nip05?> loadNip05(String identifier);
}
