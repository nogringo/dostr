import 'dart:io';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:test/test.dart';

void main() {
  // https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
  final rows = File('test/bip340.vectors.csv')
      .readAsLinesSync()
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
          expect(Bip340.getPublicKey(secretKey), publicKey);
        });

        test('signs', () {
          expect(Bip340.sign(message, secretKey, auxRand: auxRand), signature);
        });
      }

      test('verifies to $result', () {
        expect(Bip340.verify(message, signature, publicKey), result == 'true');
      });
    });
  }

  test('rejects a private key out of range', () {
    for (final privateKey in [
      '0' * 64,
      'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
      'z' * 64,
    ]) {
      expect(() => Bip340.getPublicKey(privateKey), throwsFormatException);
      expect(() => Bip340.sign('00' * 32, privateKey), throwsFormatException);
    }
  });

  test('verify returns false on malformed input', () {
    final keyPair = Bip340.generatePrivateKey();
    final message = '00' * 32;
    final signature = Bip340.sign(message, keyPair.privateKey!);

    expect(Bip340.verify(message, signature, keyPair.publicKey), isTrue);
    expect(Bip340.verify(message, signature, null), isFalse);
    expect(Bip340.verify(message, signature, 'zz'), isFalse);
    expect(Bip340.verify('0', signature, keyPair.publicKey), isFalse);
    expect(
      Bip340.verify(message, '${signature}00', keyPair.publicKey),
      isFalse,
    );
  });
}
