import 'package:ndk_cashu_protocol/ndk_cashu_protocol.dart';

/// Reserved derivation counter slot for NUT-20 mint quote lock keys.
///
/// Stored alongside the per-keyset derivation counters. Cannot collide with a
/// real keyset id since keyset ids are always hex.
const String kQuoteKeyDerivationCounterSlot = 'quote-key';

/// Persistence for Cashu keysets, proofs, mint info and secret counters.
///
/// Cache managers that persist Cashu data implement it next to `CacheManager`,
/// `Cashu` then picks the NDK cache up when no storage is passed.
abstract class CashuStorage {
  Future<void> saveKeyset(CahsuKeyset keyset);

  /// get all keysets if no mintUrl is provided \
  Future<List<CahsuKeyset>> getKeysets({String? mintUrl});

  Future<void> saveProofs({
    required List<CashuProof> proofs,
    required String mintUrl,
  });

  Future<List<CashuProof>> getProofs({
    String? mintUrl,
    String? keysetId,
    CashuProofState state = CashuProofState.unspend,
  });

  Future<void> removeProofs({
    required List<CashuProof> proofs,
    required String mintUrl,
  });

  Future<void> saveMintInfo({required CashuMintInfo mintInfo});

  Future<void> removeMintInfo({required String mintUrl});

  /// return all if no mintUrls are provided
  Future<List<CashuMintInfo>?> getMintInfos({List<String>? mintUrls});

  Future<int> getCashuSecretCounter({
    required String mintUrl,
    required String keysetId,
  });

  Future<void> setCashuSecretCounter({
    required String mintUrl,
    required String keysetId,
    required int counter,
  });
}
