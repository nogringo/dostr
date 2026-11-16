import 'package:dostr_secp256k1/dostr_secp256k1.dart';

import 'cashu_tools.dart';

/// A secp256k1 keypair as hex, with the public key compressed.
class CashuKeypair {
  final String privateKey;
  final String publicKey;

  CashuKeypair({required this.privateKey, required this.publicKey});

  /// Builds a keypair from a private key hex string by deriving the public key.
  static CashuKeypair fromPrivateKeyHex(String privateKeyHex) {
    final pubkeyHex = CashuTools.ecPointToHex(derivePublicKey(privateKeyHex));
    return CashuKeypair(privateKey: privateKeyHex, publicKey: pubkeyHex);
  }

  static CashuKeypair generateCashuKeyPair() {
    final privKey = CashuTools.randomScalar()
        .toRadixString(16)
        .padLeft(64, '0');

    final pubkeyHex = CashuTools.ecPointToHex(derivePublicKey(privKey));

    return CashuKeypair(privateKey: privKey, publicKey: pubkeyHex);
  }

  static Secp256k1Point derivePublicKey(String privateKeyHex) {
    return Secp256k1Point.generator * BigInt.parse(privateKeyHex, radix: 16);
  }

  factory CashuKeypair.fromJson(Map<String, dynamic> json) {
    return CashuKeypair(
      privateKey: json['privateKey'] as String,
      publicKey: json['publicKey'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'privateKey': privateKey, 'publicKey': publicKey};
  }
}
