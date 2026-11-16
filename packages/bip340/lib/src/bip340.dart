import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';
import 'package:dostr_secp256k1/dostr_secp256k1.dart';

import 'key_pair.dart';

final _n = secp256k1Order;
final _p = secp256k1FieldPrime;
final _keyPattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _signaturePattern = RegExp(r'^[0-9a-fA-F]{128}$');
final _hexPattern = RegExp(r'^(?:[0-9a-fA-F]{2})*$');
final _auxTag = _tagHash('BIP0340/aux');
final _nonceTag = _tagHash('BIP0340/nonce');
final _challengeTag = _tagHash('BIP0340/challenge');

/// BIP-340 Schnorr signatures, with keys, messages and signatures in hex.
/// https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki
///
/// None of it runs in constant time.
class Bip340 {
  /// Signs [message] with [privateKey] and returns the 64-byte signature.
  ///
  /// Throws a [FormatException] when [privateKey] is not a valid private key
  /// or [message] is not hex. [auxRand] is for test vectors only: each
  /// signature takes 32 fresh random bytes by default.
  static String sign(String message, String privateKey, {String? auxRand}) {
    final secret = _privateKeyScalar(privateKey);
    final publicPoint = Secp256k1Point.generator * secret;
    final d = publicPoint.y.isEven ? secret : _n - secret;
    final px = _bytes32(publicPoint.x);
    final m = hexToBytes(message);
    final aux = auxRand == null ? _secureRandomBytes(32) : hexToBytes(auxRand);
    if (aux.length != 32) {
      throw ArgumentError('must be 32 bytes', 'auxRand');
    }

    final t = _xor(_bytes32(d), _taggedHash(_auxTag, [aux]));
    final nonce = _toBigInt(_taggedHash(_nonceTag, [t, px, m])) % _n;
    if (nonce == BigInt.zero) {
      throw StateError('The nonce is zero');
    }
    final r = Secp256k1Point.generator * nonce;
    final k = r.y.isEven ? nonce : _n - nonce;
    final rx = _bytes32(r.x);
    final e = _toBigInt(_taggedHash(_challengeTag, [rx, px, m])) % _n;
    return bytesToHex([...rx, ..._bytes32((k + e * d) % _n)]);
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
    final point = Secp256k1Point.fromX(BigInt.parse(publicKey, radix: 16));
    final rHex = signature.substring(0, 64);
    final r = BigInt.parse(rHex, radix: 16);
    final s = BigInt.parse(signature.substring(64), radix: 16);
    if (point == null || r >= _p || s >= _n) {
      return false;
    }

    final challenge = _taggedHash(_challengeTag, [
      hexToBytes(rHex),
      hexToBytes(publicKey),
      hexToBytes(message),
    ]);
    final e = _toBigInt(challenge) % _n;
    final rPoint = Secp256k1Point.generator * s + point * (_n - e);
    return !rPoint.isInfinity && rPoint.y.isEven && rPoint.x == r;
  }

  /// The x-only public key of [privateKey].
  ///
  /// Throws a [FormatException] when [privateKey] is not a valid private key.
  static String getPublicKey(String privateKey) {
    final point = Secp256k1Point.generator * _privateKeyScalar(privateKey);
    return bytesToHex(_bytes32(point.x));
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
  return scalar != BigInt.zero && scalar < _n;
}

BigInt _privateKeyScalar(String privateKey) {
  if (!_isPrivateKey(privateKey)) {
    throw const FormatException('Not a valid private key');
  }
  return BigInt.parse(privateKey, radix: 16);
}

List<int> _tagHash(String tag) => sha256.convert(utf8.encode(tag)).bytes;

List<int> _taggedHash(List<int> tagHash, List<List<int>> parts) => sha256
    .convert([...tagHash, ...tagHash, for (final part in parts) ...part])
    .bytes;

List<int> _bytes32(BigInt value) =>
    hexToBytes(value.toRadixString(16).padLeft(64, '0'));

BigInt _toBigInt(List<int> bytes) => BigInt.parse(bytesToHex(bytes), radix: 16);

List<int> _xor(List<int> a, List<int> b) => [
  for (var i = 0; i < a.length; i++) a[i] ^ b[i],
];

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}
