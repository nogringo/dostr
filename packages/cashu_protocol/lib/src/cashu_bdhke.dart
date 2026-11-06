import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'entities/cashu_keyset.dart';
import 'entities/cashu_blinded_message.dart';
import 'entities/cashu_blinded_signature.dart';
import 'entities/cashu_proof.dart';

import 'cashu_key_derivation.dart';
import 'cashu_seed.dart';
import 'cashu_tools.dart';

typedef BlindMessageResult = (String blindedMessageHex, BigInt r);

class CashuBdhke {
  /// NUT-13 outputs for [amounts], one counter from [nextCounter] each. A
  /// reused counter derives an output the mint already signed.
  static Future<List<CashuBlindedMessageItem>> createBlindedMsgForAmounts({
    required String keysetId,
    required List<int> amounts,
    required CashuSeed cashuSeed,
    required CashuKeyDerivation cashuSeedSecretGenerator,
    required Future<int> Function() nextCounter,
  }) async {
    final seedBytes = Uint8List.fromList(cashuSeed.getSeedBytes());
    final items = <CashuBlindedMessageItem>[];

    for (final amount in amounts) {
      final derived = await cashuSeedSecretGenerator.deriveSecret(
        seedBytes: seedBytes,
        counter: await nextCounter(),
        keysetId: keysetId,
      );

      final (blindedMessageHex, r) = blindMessage(
        derived.secretHex,
        r: BigInt.parse(derived.blindingHex, radix: 16),
      );

      items.add(
        CashuBlindedMessageItem(
          blindedMessage: CashuBlindedMessage(
            id: keysetId,
            amount: amount,
            blindedMessage: blindedMessageHex,
          ),
          secret: derived.secretHex,
          r: r,
          amount: amount,
        ),
      );
    }

    return items;
  }

  static BlindMessageResult blindMessage(String secret, {BigInt? r}) {
    final Y = CashuTools.hashToCurve(secret);

    r ??= CashuTools.randomScalar();

    final rG = CashuTools.fastGMultiply(r);
    final ECPoint? blindedMessage = Y + rG;

    if (blindedMessage == null) {
      throw Exception('Failed to compute blinded message');
    }

    final String blindedMessageHex = CashuTools.ecPointToHex(blindedMessage);
    return (blindedMessageHex, r);
  }

  static ECPoint? unblindingSignature({
    required String cHex,
    required String kHex,
    required BigInt r,
  }) {
    final cPoint = CashuTools.pointFromHexString(cHex);
    final K = CashuTools.pointFromHexString(kHex);
    final rK = K * r;
    if (rK == null) return null;
    return cPoint - rK;
  }

  /// The mint returns [mintSignatures] in the order it got the outputs, so the
  /// i-th one signs the i-th of [blindedMessages]. NUT-08 change can hold
  /// fewer, with amounts the mint imprinted on the blank outputs.
  static List<CashuProof> unblindSignatures({
    required List<CashuBlindedSignature> mintSignatures,
    required List<CashuBlindedMessageItem> blindedMessages,
    required CahsuKeyset mintPublicKeys,
  }) {
    if (mintSignatures.length > blindedMessages.length) {
      throw Exception(
        'Mismatched lengths: ${mintSignatures.length} signatures, ${blindedMessages.length} messages',
      );
    }

    final keysByAmount = {
      for (final keyPair in mintPublicKeys.mintKeyPairs)
        keyPair.amount: keyPair.pubkey,
    };

    return [
      for (final (i, signature) in mintSignatures.indexed)
        _unblind(
          signature,
          blindedMessages[i],
          mintPublicKeys.id,
          keysByAmount,
        ),
    ];
  }

  static CashuProof _unblind(
    CashuBlindedSignature signature,
    CashuBlindedMessageItem message,
    String keysetId,
    Map<int, String> keysByAmount,
  ) {
    final mintPubKey = keysByAmount[signature.amount];
    if (mintPubKey == null) {
      throw Exception('No mint public key for amount ${signature.amount}');
    }

    final unblindedSig = unblindingSignature(
      cHex: signature.blindedSignature,
      kHex: mintPubKey,
      r: message.r,
    );
    if (unblindedSig == null) {
      throw Exception('Failed to unblind signature');
    }

    return CashuProof(
      secret: message.secret,
      amount: signature.amount,
      unblindedSig: CashuTools.ecPointToHex(unblindedSig),
      keysetId: keysetId,
    );
  }
}
