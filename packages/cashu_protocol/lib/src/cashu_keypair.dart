import 'package:pointycastle/export.dart';

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

  static ECPoint derivePublicKey(String privateKeyHex) {
    // hex private key to BigInt
    final privateKeyInt = BigInt.parse(privateKeyHex, radix: 16);

    final G = CashuTools.getG();

    // calculate public key: pubkey = privKey * G
    final publicKeyPoint = G * privateKeyInt;

    return publicKeyPoint!;
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
