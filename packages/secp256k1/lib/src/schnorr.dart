import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'bytes.dart';
import 'secp256k1.dart';

final _n = secp256k1Order;
final _auxTag = _tagHash('BIP0340/aux');
final _nonceTag = _tagHash('BIP0340/nonce');
final _challengeTag = _tagHash('BIP0340/challenge');

/// BIP-340 Schnorr signatures, with keys and signatures as bytes.
/// https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki
///
/// None of it runs in constant time.
abstract final class Schnorr {
  /// The 32-byte x-only public key of [privateKey].
  ///
  /// Throws an [ArgumentError] when [privateKey] is not 32 bytes between 1
  /// and n - 1.
  static Uint8List publicKey(List<int> privateKey) =>
      bigIntTo32Bytes((Secp256k1Point.generator * _secret(privateKey)).x);

  /// The 64-byte signature of [message], of any length, with [privateKey].
  ///
  /// Throws an [ArgumentError] when [privateKey] is not 32 bytes between 1
  /// and n - 1. [auxRand] is for test vectors only: each signature takes 32
  /// fresh random bytes by default.
  static Uint8List sign(
    List<int> message,
    List<int> privateKey, {
    List<int>? auxRand,
  }) {
    final secret = _secret(privateKey);
    final publicPoint = Secp256k1Point.generator * secret;
    final d = publicPoint.y.isEven ? secret : _n - secret;
    final px = bigIntTo32Bytes(publicPoint.x);
    final aux = auxRand ?? _secureRandomBytes(32);
    if (aux.length != 32) {
      throw ArgumentError('must be 32 bytes', 'auxRand');
    }

    final t = _xor(bigIntTo32Bytes(d), _taggedHash(_auxTag, [aux]));
    final nonce = bytesToBigInt(_taggedHash(_nonceTag, [t, px, message])) % _n;
    if (nonce == BigInt.zero) {
      throw StateError('The nonce is zero');
    }
    final r = Secp256k1Point.generator * nonce;
    final k = r.y.isEven ? nonce : _n - nonce;
    final rx = bigIntTo32Bytes(r.x);
    final e = bytesToBigInt(_taggedHash(_challengeTag, [rx, px, message])) % _n;
    return Uint8List.fromList([...rx, ...bigIntTo32Bytes((k + e * d) % _n)]);
  }

  /// Whether the 64-byte [signature] signs [message] with the 32-byte x-only
  /// [publicKey].
  ///
  /// It returns false, and never throws, on a key or a signature of the wrong
  /// length.
  static bool verify(
    List<int> message,
    List<int> signature,
    List<int> publicKey,
  ) {
    if (signature.length != 64 || publicKey.length != 32) {
      return false;
    }
    final point = Secp256k1Point.fromX(bytesToBigInt(publicKey));
    final rBytes = signature.sublist(0, 32);
    final r = bytesToBigInt(rBytes);
    final s = bytesToBigInt(signature.sublist(32));
    if (point == null || r >= secp256k1FieldPrime || s >= _n) {
      return false;
    }

    final challenge = _taggedHash(_challengeTag, [rBytes, publicKey, message]);
    final rPoint =
        Secp256k1Point.generator * s - point * (bytesToBigInt(challenge) % _n);
    return !rPoint.isInfinity && rPoint.y.isEven && rPoint.x == r;
  }
}

BigInt _secret(List<int> privateKey) {
  final secret = privateKey.length == 32
      ? bytesToBigInt(privateKey)
      : BigInt.zero;
  if (secret == BigInt.zero || secret >= _n) {
    throw ArgumentError('must be 32 bytes between 1 and n - 1', 'privateKey');
  }
  return secret;
}

List<int> _tagHash(String tag) => sha256.convert(utf8.encode(tag)).bytes;

List<int> _taggedHash(List<int> tagHash, List<List<int>> parts) => sha256
    .convert([...tagHash, ...tagHash, for (final part in parts) ...part])
    .bytes;

List<int> _xor(List<int> a, List<int> b) => [
  for (var i = 0; i < a.length; i++) a[i] ^ b[i],
];

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}
