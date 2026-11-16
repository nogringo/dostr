import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dostr_secp256k1/dostr_secp256k1.dart';

import 'entities/cashu_blinded_message.dart';
import 'entities/cashu_keyset.dart';
import 'entities/cashu_proof.dart';

/// Cashu helpers: secp256k1 points, hash_to_curve, amounts, keysets and mint
/// URLs.
class CashuTools {
  static const String apiVersion = 'v1';
  static const String hashToCurveDomainSeparator =
      'Secp256k1_HashToCurve_Cashu_';

  static final Random _random = Random.secure();

  static String composeUrl({
    required String mintUrl,
    required String path,
    String version = '$apiVersion/',
  }) {
    return '$mintUrl/$version$path';
  }

  /// Splits an amount into a list of powers of two.
  /// eg, 5 will be split into [1, 4]
  static List<int> splitAmount(int value) {
    return [
      for (int i = 0; value > 0; i++, value >>= 1)
        if (value & 1 == 1) 1 << i,
    ];
  }

  static Secp256k1Point hashToCurve(String hash) {
    const maxAttempt = 65536;

    final msgHash = sha256.convert([
      ...utf8.encode(hashToCurveDomainSeparator),
      ...utf8.encode(hash),
    ]).bytes;

    for (int counter = 0; counter < maxAttempt; counter++) {
      final counterBytes = Uint8List(4)
        ..buffer.asByteData().setUint32(0, counter, Endian.little);
      final x = sha256.convert([...msgHash, ...counterBytes]).bytes;

      final point = Secp256k1Point.fromSec1([2, ...x]);
      if (point != null) {
        return point;
      }
    }

    throw Exception('Failed to find a valid point after $maxAttempt attempts');
  }

  /// The point that [hexString] encodes in SEC1. Throws a [FormatException]
  /// when it encodes no point of secp256k1.
  static Secp256k1Point pointFromHexString(String hexString) {
    return Secp256k1Point.fromSec1(hexToBytes(hexString)) ??
        (throw FormatException('Not a secp256k1 point', hexString));
  }

  static String ecPointToHex(Secp256k1Point point, {bool compressed = true}) {
    return bytesToHex(point.toSec1(compressed: compressed));
  }

  static String createMintSignature({
    required String quote,
    required List<CashuBlindedMessage> blindedMessagesOutputs,
    required String privateKeyHex,
  }) {
    final StringBuffer messageBuffer = StringBuffer();

    // add quote id
    messageBuffer.write(quote);

    // add each B_ field(hex strings)
    for (final output in blindedMessagesOutputs) {
      messageBuffer.write(output.blindedMessage);
    }

    final String messageToSign = messageBuffer.toString();

    final messageHash = sha256.convert(utf8.encode(messageToSign)).bytes;
    return bytesToHex(Schnorr.sign(messageHash, hexToBytes(privateKeyHex)));
  }

  static Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  /// A uniformly random secp256k1 scalar in `[1, n - 1]`.
  static BigInt randomScalar() {
    while (true) {
      final scalar = BigInt.parse(bytesToHex(randomBytes(32)), radix: 16);
      if (scalar > BigInt.zero && scalar < secp256k1Order) return scalar;
    }
  }

  static Uint8List hexToBytes(String hex) {
    if (hex.length.isOdd) {
      throw FormatException('Hex string has an odd length', hex);
    }
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _hexDigit(hex, 2 * i) << 4 | _hexDigit(hex, 2 * i + 1);
    }
    return bytes;
  }

  static int _hexDigit(String hex, int index) {
    final digit = int.tryParse(hex[index], radix: 16);
    if (digit == null) throw FormatException('Invalid hex digit', hex, index);
    return digit;
  }

  static String bytesToHex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Filters keysets by unit and returns the active keyset.
  /// Throws an exception if no keysets are found with the specified unit
  /// or if no active keyset is found.
  static CashuKeyset filterKeysetsByUnitActive({
    required List<CashuKeyset> keysets,
    required String unit,
  }) {
    final keysetsFiltered = keysets
        .where((keyset) => keyset.unit == unit)
        .toList();

    if (keysetsFiltered.isEmpty) {
      throw Exception('No keysets found with unit: $unit');
    }

    try {
      return keysetsFiltered.firstWhere((keyset) => keyset.active);
    } catch (_) {
      throw Exception('No active keyset found for unit: $unit');
    }
  }

  /// filters keysets by unit
  static List<CashuKeyset> filterKeysetsByUnit({
    required List<CashuKeyset> keysets,
    required String unit,
  }) {
    return keysets.where((keyset) => keyset.unit == unit).toList();
  }

  /// Sums the amounts of all proofs in the list. \
  /// Returns the total amount.
  static int sumOfProofs({required List<CashuProof> proofs}) {
    return proofs.fold(0, (sum, proof) => sum + proof.amount);
  }

  /// Calculates the number of blank outputs needed for a given fee reserve.
  static int calculateNumberOfBlankOutputs(int feeReserveSat) {
    if (feeReserveSat < 0) {
      throw Exception("Fee reserve can't be negative.");
    }

    if (feeReserveSat == 0) {
      return 0;
    }

    return max((log(feeReserveSat) / ln2).ceil(), 1);
  }

  static List<CashuProof> filterProofsByUnit({
    required List<CashuProof> proofs,
    required String unit,
    required List<CashuKeyset> keysets,
  }) {
    return proofs.where((proof) {
      final keyset = keysets.firstWhere(
        (keyset) => keyset.id == proof.keysetId,
        orElse: () => throw Exception('Keyset not found for proof: $proof'),
      );
      return keyset.unit == unit;
    }).toList();
  }
}
