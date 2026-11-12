import 'dart:math';

import 'package:bip340/bip340.dart' as bip340;
import 'package:dostr_nip01/dostr_nip01.dart';

import 'key_pair.dart';

class Bip340 {
  /// [message] is a hex string
  /// [privateKey] is a  32-bytes hex encoded string
  /// returns a hex string
  static String sign(String message, String privateKey) {
    final aux = _secureRandomHex(32);
    return bip340.sign(privateKey, message, aux);
  }

  /// [message] is a hex string
  /// [signature] is a hex string
  /// [publicKey] is a 32-bytes hex-encoded string
  /// true if the signature is valid otherwise false
  static bool verify(String message, String signature, String? publicKey) {
    if (publicKey == null) {
      return false;
    }
    return bip340.verify(publicKey, message, signature);
  }

  /// [privateKey] is a 32-bytes hex-encoded string
  /// returns the public key in form of 32-bytes hex-encoded string
  static String getPublicKey(String privateKey) {
    return bip340.getPublicKey(privateKey);
  }

  /// generates a new private key with a secure random generator
  static KeyPair generatePrivateKey() {
    final privKey = _secureRandomHex(32);
    final pubKey = getPublicKey(privKey);

    return KeyPair(privKey, pubKey);
  }

  /// this method signs the event with the provided private key
  /// mainly used for testing purposes, please use the account usecase to sign events!
  static Nip01Event signEvent({
    required Nip01Event event,
    required String privateKey,
  }) {
    final id = event.payloadId;

    final signature = sign(id, privateKey);
    return event.copyWith(id: id, sig: signature);
  }
}

String _secureRandomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
