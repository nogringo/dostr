import 'dart:typed_data';

import 'package:dostr_secp256k1/dostr_secp256k1.dart';
import 'package:test/test.dart';

import 'bip340_vectors.dart';

Uint8List _bytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  final rows = bip340Vectors
      .split('\n')
      .skip(1)
      .where((line) => line.isNotEmpty)
      .map((line) => line.toLowerCase().split(','));

  for (final row in rows) {
    final [index, secretKey, publicKey, auxRand, message, signature, result] =
        row.sublist(0, 7);
    final comment = row.sublist(7).join(',');

    group('vector $index${comment.isEmpty ? '' : ' ($comment)'}', () {
      if (secretKey.isNotEmpty) {
        test('derives the public key', () {
          expect(Schnorr.publicKey(_bytes(secretKey)), _bytes(publicKey));
        });

        test('signs', () {
          expect(
            Schnorr.sign(
              _bytes(message),
              _bytes(secretKey),
              auxRand: _bytes(auxRand),
            ),
            _bytes(signature),
          );
        });
      }

      test('verifies to $result', () {
        expect(
          Schnorr.verify(_bytes(message), _bytes(signature), _bytes(publicKey)),
          result == 'true',
        );
      });
    });
  }

  test('rejects a private key out of range or of the wrong length', () {
    for (final privateKey in [
      Uint8List(32),
      _bytes(
        'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
      ),
      Uint8List(31)..[30] = 1,
    ]) {
      expect(() => Schnorr.publicKey(privateKey), throwsArgumentError);
      expect(
        () => Schnorr.sign(Uint8List(32), privateKey),
        throwsArgumentError,
      );
    }
  });

  test('verify returns false on a key or a signature of the wrong length', () {
    final privateKey = Uint8List(32)..[31] = 7;
    final publicKey = Schnorr.publicKey(privateKey);
    final message = Uint8List(32);
    final signature = Schnorr.sign(message, privateKey);

    expect(Schnorr.verify(message, signature, publicKey), isTrue);
    expect(Schnorr.verify(message, signature.sublist(1), publicKey), isFalse);
    expect(Schnorr.verify(message, signature, publicKey.sublist(1)), isFalse);
  });
}
