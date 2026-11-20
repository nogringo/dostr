import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dostr_nip49/src/hex.dart';
import 'package:dostr_nip49/src/xchacha20_poly1305.dart';
import 'package:test/test.dart';

Uint8List _hex(String hex) => tryHexToBytes(hex)!;

final _aeadKey = _hex(
  '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f',
);
final _aeadAad = _hex('50515253c0c1c2c3c4c5c6c7');
final _sunscreen = utf8.encode(
  "Ladies and Gentlemen of the class of '99: If I could offer you only one "
  'tip for the future, sunscreen would be it.',
);

BigInt _littleEndian(List<int> bytes) =>
    bytes.reversed.fold(BigInt.zero, (n, byte) => n << 8 | BigInt.from(byte));

/// Poly1305 as RFC 8439 defines it, on big integers.
Uint8List _poly1305Definition(List<int> key, List<int> message) {
  final p = (BigInt.one << 130) - BigInt.from(5);
  final r =
      _littleEndian(key.sublist(0, 16)) &
      BigInt.parse('0ffffffc0ffffffc0ffffffc0fffffff', radix: 16);
  var accumulator = BigInt.zero;
  for (var offset = 0; offset < message.length; offset += 16) {
    final block = message.sublist(offset, min(offset + 16, message.length));
    accumulator = (accumulator + _littleEndian([...block, 1])) * r % p;
  }
  final tag = accumulator + _littleEndian(key.sublist(16, 32));
  return Uint8List.fromList([
    for (var i = 0; i < 16; i++) (tag >> 8 * i).toUnsigned(8).toInt(),
  ]);
}

void main() {
  test('HChaCha20 matches the draft-irtf-cfrg-xchacha vector', () {
    expect(
      bytesToHex(
        hchacha20(
          _hex(
            '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
          ),
          _hex('000000090000004a0000000031415927'),
        ),
      ),
      '82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc',
    );
  });

  group('ChaCha20-Poly1305 with the RFC 8439 vector', () {
    final nonce = _hex('070000004041424344454647');
    const sealed =
        'd31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116'
        '1ae10b594f09e26a7e902ecbd0600691';

    test('encrypts', () {
      expect(
        bytesToHex(
          chacha20Poly1305Encrypt(_aeadKey, nonce, _sunscreen, _aeadAad),
        ),
        sealed,
      );
    });

    test('decrypts', () {
      expect(
        chacha20Poly1305Decrypt(_aeadKey, nonce, _hex(sealed), _aeadAad),
        _sunscreen,
      );
    });
  });

  group('XChaCha20-Poly1305 with the draft-irtf-cfrg-xchacha vector', () {
    final nonce = _hex('404142434445464748494a4b4c4d4e4f5051525354555657');
    final sealed = _hex(
      'bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b4522f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff921f9664c97637da9768812f615c68b13b52e'
      'c0875924c1c7987947deafd8780acf49',
    );

    test('encrypts', () {
      expect(
        xchacha20Poly1305Encrypt(_aeadKey, nonce, _sunscreen, _aeadAad),
        sealed,
      );
    });

    test('decrypts', () {
      expect(
        xchacha20Poly1305Decrypt(_aeadKey, nonce, sealed, _aeadAad),
        _sunscreen,
      );
    });

    test('rejects a change to the ciphertext, tag, nonce or aad', () {
      for (final index in [0, 57, sealed.length - 17, sealed.length - 1]) {
        final changed = Uint8List.fromList(sealed)..[index] ^= 0x80;
        expect(
          xchacha20Poly1305Decrypt(_aeadKey, nonce, changed, _aeadAad),
          isNull,
          reason: 'byte $index',
        );
      }
      final otherNonce = Uint8List.fromList(nonce)..[23] ^= 1;
      expect(
        xchacha20Poly1305Decrypt(_aeadKey, otherNonce, sealed, _aeadAad),
        isNull,
      );
      expect(
        xchacha20Poly1305Decrypt(_aeadKey, nonce, sealed, [..._aeadAad, 0]),
        isNull,
      );
    });

    test('rejects input shorter than a tag', () {
      expect(
        xchacha20Poly1305Decrypt(_aeadKey, nonce, Uint8List(15), _aeadAad),
        isNull,
      );
    });
  });

  group('Poly1305', () {
    test('matches the RFC 8439 vector', () {
      expect(
        bytesToHex(
          poly1305(
            _hex(
              '85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b',
            ),
            utf8.encode('Cryptographic Forum Research Group'),
          ),
        ),
        'a8061dc1305136c6c22b8baf0c0127a9',
      );
    });

    test('reduces modulo 2^130 - 5 at its edges', () {
      final rIsTwo = Uint8List(32)..[0] = 2;
      final sIsMax = Uint8List.fromList(rIsTwo)..fillRange(16, 32, 0xff);
      final allOnes = List.filled(16, 0xff);

      // (2^129 - 1) * 2 is 2^130 - 2, which reduces to 3.
      expect(bytesToHex(poly1305(rIsTwo, allOnes)), '03${'00' * 15}');
      // (2^128 + 2) * 2 + s overflows 2^128.
      expect(
        bytesToHex(poly1305(sIsMax, [2, ...List.filled(15, 0)])),
        '03${'00' * 15}',
      );
      // (2^129 - 3) * 2 is 2^130 - 6, just below the modulus.
      expect(
        bytesToHex(poly1305(rIsTwo, [0xfd, ...allOnes.skip(1)])),
        'fa${'ff' * 15}',
      );
    });

    test('matches the definition on big integers', () {
      final random = Random(1);
      List<int> bytes(int length, [int? fill]) =>
          List.generate(length, (_) => fill ?? random.nextInt(256));

      for (var i = 0; i < 300; i++) {
        final key = bytes(32);
        final message = bytes(random.nextInt(100));
        expect(
          poly1305(Uint8List.fromList(key), message),
          _poly1305Definition(key, message),
        );
      }
      for (final fill in [0x00, 0xfd, 0xfe, 0xff]) {
        for (final length in [0, 1, 15, 16, 17, 31, 32, 33, 64, 80]) {
          final key = [...bytes(16, 0xff), ...bytes(16, 0xff)];
          final message = bytes(length, fill);
          expect(
            poly1305(Uint8List.fromList(key), message),
            _poly1305Definition(key, message),
            reason: 'fill $fill, length $length',
          );
        }
      }
    });
  });
}
