import 'dart:math';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';
import 'package:dostr_secp256k1/dostr_secp256k1.dart';
import 'package:dostr_signer/dostr_signer.dart';

final _keyPattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _signaturePattern = RegExp(r'^[0-9a-fA-F]{128}$');
final _hexPattern = RegExp(r'^(?:[0-9a-fA-F]{2})*$');

/// BIP-340 Schnorr signatures, with keys, messages and signatures in hex, on
/// the [Schnorr] of `dostr_secp256k1`.
abstract final class Bip340 {
  /// Signs [message] with [privateKey] and returns the 64-byte signature.
  ///
  /// Throws a [FormatException] when [privateKey] is not a valid private key
  /// or [message] is not hex. [auxRand] is for test vectors only: each
  /// signature takes 32 fresh random bytes by default.
  static String sign({
    required String message,
    required String privateKey,
    String? auxRand,
  }) {
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
  static bool verify({
    required String message,
    required String signature,
    required String publicKey,
  }) {
    if (!_keyPattern.hasMatch(publicKey) ||
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

  /// A new key pair, from a secure random generator.
  static KeyPair generateKeyPair() {
    String privateKey;
    do {
      privateKey = bytesToHex(_secureRandomBytes(32));
    } while (!_isPrivateKey(privateKey));
    return (privateKey: privateKey, publicKey: getPublicKey(privateKey));
  }

  /// [event] with the id of its payload, whatever id it holds, signed with
  /// [privateKey].
  ///
  /// Throws a [FormatException] when [privateKey] is not a valid private key,
  /// and an [ArgumentError] when the pubkey of [event] is not its public key.
  static Nip01Event signEvent({
    required Nip01Event event,
    required String privateKey,
  }) {
    final publicKey = getPublicKey(privateKey);
    if (event.pubkey != publicKey) {
      throw ArgumentError.value(
        event.pubkey,
        'event.pubkey',
        'is not the pubkey of the private key, $publicKey',
      );
    }
    return signPayload(event, privateKey);
  }
}

// For a caller that checked the pubkey of the event.
Nip01Event signPayload(Nip01Event event, String privateKey) {
  final id = event.payloadId;
  return event.copyWith(
    id: id,
    sig: Bip340.sign(message: id, privateKey: privateKey),
  );
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
