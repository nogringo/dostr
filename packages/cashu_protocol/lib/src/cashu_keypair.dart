import 'package:pointycastle/export.dart';

import 'cashu_tools.dart';

class CashuKeypair {
  final String privateKey;
  final String publicKey;

  CashuKeypair({required this.privateKey, required this.publicKey});

  /// Builds a keypair from a private key hex string by deriving the public key.
  static CashuKeypair fromPrivateKeyHex(String privateKeyHex) {
    final pubKeyHex = CashuTools.ecPointToHex(derivePublicKey(privateKeyHex));
    return CashuKeypair(privateKey: privateKeyHex, publicKey: pubKeyHex);
  }

  static CashuKeypair generateCashuKeyPair() {
    final privKey = CashuTools.randomScalar()
        .toRadixString(16)
        .padLeft(64, '0');

    final pubKeyHex = CashuTools.ecPointToHex(derivePublicKey(privKey));

    return CashuKeypair(privateKey: privKey, publicKey: pubKeyHex);
  }

  static ECPoint derivePublicKey(String privateKeyHex) {
    // hex private key to BigInt
    final privateKeyInt = BigInt.parse(privateKeyHex, radix: 16);

    final G = CashuTools.getG();

    // calculate public key: pubKey = privKey * G
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
