import 'dart:math';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';
import 'package:dostr_secp256k1/dostr_secp256k1.dart';

import 'key_pair.dart';

final _keyPattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _signaturePattern = RegExp(r'^[0-9a-fA-F]{128}$');
final _hexPattern = RegExp(r'^(?:[0-9a-fA-F]{2})*$');

/// BIP-340 Schnorr signatures, with keys, messages and signatures in hex, on
/// the [Schnorr] of `dostr_secp256k1`.
class Bip340 {
  /// Signs [message] with [privateKey] and returns the 64-byte signature.
  ///
  /// Throws a [FormatException] when [privateKey] is not a valid private key
  /// or [message] is not hex. [auxRand] is for test vectors only: each
  /// signature takes 32 fresh random bytes by default.
  static String sign(String message, String privateKey, {String? auxRand}) {
    final signature = Schnorr.sign(
      hexToBytes(message),
      _privateKeyBytes(privateKey),
      auxRand: auxRand == null ? null : hexToBytes(auxRand),
    );
    return bytesToHex(signature);
  }

  /// Whether [signature] signs [message] with the x-only [publicKey].
  ///
  /// It returns false, and never throws, on malformed input.
  static bool verify(String message, String signature, String? publicKey) {
    if (publicKey == null ||
        !_keyPattern.hasMatch(publicKey) ||
        !_signaturePattern.hasMatch(signature) ||
        !_hexPattern.hasMatch(message)) {
      return false;
    }
    return Schnorr.verify(
      hexToBytes(message),
      hexToBytes(signature),
      hexToBytes(publicKey),
    );
  }

  /// The x-only public key of [privateKey].
  ///
  /// Throws a [FormatException] when [privateKey] is not a valid private key.
  static String getPublicKey(String privateKey) {
    return bytesToHex(Schnorr.publicKey(_privateKeyBytes(privateKey)));
  }

  /// generates a new private key with a secure random generator
  static KeyPair generatePrivateKey() {
    String privateKey;
    do {
      privateKey = bytesToHex(_secureRandomBytes(32));
    } while (!_isPrivateKey(privateKey));
    return KeyPair(privateKey, getPublicKey(privateKey));
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

bool _isPrivateKey(String privateKey) {
  if (!_keyPattern.hasMatch(privateKey)) {
    return false;
  }
  final scalar = BigInt.parse(privateKey, radix: 16);
  return scalar != BigInt.zero && scalar < secp256k1Order;
}

List<int> _privateKeyBytes(String privateKey) {
  if (!_isPrivateKey(privateKey)) {
    throw const FormatException('Not a valid private key');
  }
  return hexToBytes(privateKey);
}

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}
