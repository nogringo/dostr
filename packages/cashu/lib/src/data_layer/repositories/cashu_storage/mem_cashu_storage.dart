import '../../../domain_layer/entities/cashu/cashu_keyset.dart';
import '../../../domain_layer/entities/cashu/cashu_mint_info.dart';
import '../../../domain_layer/entities/cashu/cashu_proof.dart';
import '../../../domain_layer/repositories/cashu_storage.dart';

/// In memory [CashuStorage], lost on restart.
class MemCashuStorage implements CashuStorage {
  /// String for mint Url
  Map<String, Set<CahsuKeyset>> cashuKeysets = {};

  /// String for mint Url
  Map<String, Set<CashuProof>> cashuProofs = {};

  Set<CashuMintInfo> cashuMintInfos = {};

  /// Key is a combination of mintUrl and keysetId, value is the counter
  final Map<String, int> _cashuSecretCounters = {};

  @override
  Future<List<CahsuKeyset>> getKeysets({String? mintUrl}) {
    if (cashuKeysets.containsKey(mintUrl)) {
      return Future.value(cashuKeysets[mintUrl]?.toList() ?? []);
    } else {
      return Future.value(cashuKeysets.values.expand((e) => e).toList());
    }
  }

  @override
  Future<void> saveKeyset(CahsuKeyset keyset) {
    if (cashuKeysets.containsKey(keyset.mintUrl)) {
      cashuKeysets[keyset.mintUrl]!.add(keyset);
    } else {
      cashuKeysets[keyset.mintUrl] = {keyset};
    }
    return Future.value();
  }

  @override
  Future<List<CashuProof>> getProofs({
    String? mintUrl,
    String? keysetId,
    CashuProofState state = CashuProofState.unspend,
  }) async {
    if (cashuProofs.containsKey(mintUrl)) {
      return cashuProofs[mintUrl]!
          .where(
            (proof) =>
                proof.state == state &&
                (keysetId == null || proof.keysetId == keysetId),
          )
          .toList();
    } else {
      return cashuProofs.values
          .expand((proofs) => proofs)
          .where(
            (proof) =>
                proof.state == state &&
                (keysetId == null || proof.keysetId == keysetId),
          )
          .toList();
    }
  }

  @override
  Future<void> saveProofs({
    required List<CashuProof> proofs,
    required String mintUrl,
  }) {
    if (cashuProofs.containsKey(mintUrl)) {
      cashuProofs[mintUrl]!.addAll(proofs);
    } else {
      cashuProofs[mintUrl] = Set<CashuProof>.from(proofs);
    }
    return Future.value();
  }

  @override
  Future<void> removeProofs({
    required List<CashuProof> proofs,
    required String mintUrl,
  }) {
    if (cashuProofs.containsKey(mintUrl)) {
      final existingProofs = cashuProofs[mintUrl]!;
      for (final proof in proofs) {
        existingProofs.removeWhere((p) => p.secret == proof.secret);
      }
      if (existingProofs.isEmpty) {
        cashuProofs.remove(mintUrl);
      }

      return Future.value();
    } else {
      return Future.error('No proofs found for mint URL: $mintUrl');
    }
  }

  @override
  Future<List<CashuMintInfo>?> getMintInfos({List<String>? mintUrls}) {
    if (mintUrls == null) {
      return Future.value(cashuMintInfos.toList());
    } else {
      final result = cashuMintInfos
          .where((info) => mintUrls.any((url) => info.isMintUrl(url)))
          .toList();
      return Future.value(result.isNotEmpty ? result : null);
    }
  }

  @override
  Future<void> saveMintInfo({required CashuMintInfo mintInfo}) {
    cashuMintInfos.removeWhere(
      (info) => info.urls.any((url) => mintInfo.isMintUrl(url)),
    );
    cashuMintInfos.add(mintInfo);
    return Future.value();
  }

  @override
  Future<void> removeMintInfo({required String mintUrl}) {
    cashuMintInfos.removeWhere(
      (info) => info.urls.any((url) => info.isMintUrl(mintUrl)),
    );
    return Future.value();
  }

  @override
  Future<int> getCashuSecretCounter({
    required String mintUrl,
    required String keysetId,
  }) {
    final key = '$mintUrl|$keysetId';
    return Future.value(_cashuSecretCounters[key] ?? 0);
  }

  @override
  Future<void> setCashuSecretCounter({
    required String mintUrl,
    required String keysetId,
    required int counter,
  }) async {
    final key = '$mintUrl|$keysetId';
    _cashuSecretCounters[key] = counter;

    return;
  }
}
