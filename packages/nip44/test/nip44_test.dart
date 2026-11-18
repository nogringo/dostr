import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:dostr_nip44/dostr_nip44.dart';
import 'package:dostr_nip44/src/ecdh.dart';
import 'package:dostr_nip44/src/utils.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:test/test.dart';

Uint8List _bytes(String hexString) => Uint8List.fromList(hex.decode(hexString));

String _sha256(List<int> data) =>
    hex.encode(SHA256Digest().process(Uint8List.fromList(data)));

ECPoint _point(String privateKey) =>
    (ECCurve_secp256k1().G * BigInt.parse(privateKey, radix: 16))!;

String _publicKey(String privateKey) =>
    _point(privateKey).x!.toBigInteger()!.toRadixString(16).padLeft(64, '0');

List<Map<String, dynamic>> _cases(Map<String, dynamic> group, String name) =>
    (group[name] as List).cast<Map<String, dynamic>>();

void main() {
  // https://github.com/paulmillr/nip44/blob/main/nip44.vectors.json
  final vectorsBytes = File('test/nip44.vectors.json').readAsBytesSync();
  final vectors =
      (jsonDecode(utf8.decode(vectorsBytes)) as Map<String, dynamic>)['v2']
          as Map<String, dynamic>;
  final valid = vectors['valid'] as Map<String, dynamic>;
  final invalid = vectors['invalid'] as Map<String, dynamic>;

  test('the vectors are the ones NIP-44 publishes', () {
    expect(
      _sha256(vectorsBytes),
      '269ed0f69e4c192512cc779e78c555090cebc7c785b609e338a62afc3ce25040',
    );
  });

  group('conversationKey', () {
    for (final (i, v) in _cases(valid, 'get_conversation_key').indexed) {
      test('vector $i', () {
        expect(
          Nip44.conversationKey(privateKey: v['sec1'], publicKey: v['pub2']),
          _bytes(v['conversation_key']),
        );
      });
    }

    for (final v in _cases(invalid, 'get_conversation_key')) {
      test('rejects ${v['note']}', () {
        expect(
          () => Nip44.conversationKey(
            privateKey: v['sec1'],
            publicKey: v['pub2'],
          ),
          throwsFormatException,
        );
      });
    }

    test('is the same for x-only and SEC1 public keys', () {
      const privateKey =
          '0000000000000000000000000000000000000000000000000000000000000001';
      const peer =
          'b74e6a341fb134127272b795a08b59250e5fa45a82a2eb4095e4ce9ed5f5e214';
      final expected = Nip44.conversationKey(
        privateKey: privateKey,
        publicKey: _publicKey(peer),
      );

      for (final compressed in [true, false]) {
        final encoded = hex.encode(_point(peer).getEncoded(compressed));
        expect(
          Nip44.conversationKey(privateKey: privateKey, publicKey: encoded),
          expected,
        );
      }
    });

    test('matches the pointycastle point multiplication', () {
      final n = ECCurve_secp256k1().n;
      final random = Random(44);
      BigInt randomScalar() =>
          BigInt.parse(
                List.generate(
                  64,
                  (_) => random.nextInt(16).toRadixString(16),
                ).join(),
                radix: 16,
              ) %
              (n - BigInt.one) +
          BigInt.one;

      final peer = _point(randomScalar().toRadixString(16).padLeft(64, '0'));
      final peerPublicKey = hex.encode(peer.getEncoded(true));
      for (final scalar in [
        for (final small in [1, 2, 15, 16, 17, 255, 256]) BigInt.from(small),
        BigInt.one << 255,
        n - BigInt.two,
        n - BigInt.one,
        for (var i = 0; i < 20; i++) randomScalar(),
      ]) {
        final privateKey = scalar.toRadixString(16).padLeft(64, '0');
        expect(
          hex.encode(sharedSecret(privateKey, peerPublicKey)),
          (peer * scalar)!.x!
              .toBigInteger()!
              .toRadixString(16)
              .padLeft(64, '0'),
          reason: 'scalar $privateKey',
        );
      }
    });

    Matcher throwsWithout(String privateKey) => throwsA(
      isA<FormatException>().having(
        (e) => e.toString(),
        'toString()',
        isNot(contains(privateKey)),
      ),
    );

    test('never puts the private key in its error', () {
      for (final privateKey in [
        'z' * 64,
        'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
      ]) {
        expect(
          () => Nip44.conversationKey(
            privateKey: privateKey,
            publicKey: _publicKey('${'0' * 63}1'),
          ),
          throwsWithout(privateKey),
        );
      }
    });

    test('never puts a private key passed as the public key in its error', () {
      // 5 is a valid private key, and the x of no point.
      final privateKey = '${'0' * 63}5';

      expect(
        () => Nip44.conversationKey(
          privateKey: '${'0' * 63}1',
          publicKey: privateKey,
        ),
        throwsWithout(privateKey),
      );
    });
  });

  group('message keys', () {
    final messageKeys = valid['get_message_keys'] as Map<String, dynamic>;
    final conversationKey = _bytes(messageKeys['conversation_key']);

    for (final (i, v) in _cases(messageKeys, 'keys').indexed) {
      test('vector $i', () {
        final keys = deriveMessageKeys(conversationKey, _bytes(v['nonce']));

        expect(keys.chachaKey, _bytes(v['chacha_key']));
        expect(keys.chachaNonce, _bytes(v['chacha_nonce']));
        expect(keys.hmacKey, _bytes(v['hmac_key']));
      });
    }
  });

  group('calcPaddedLen', () {
    for (final [unpadded, padded] in (valid['calc_padded_len'] as List)) {
      test('pads $unpadded bytes to $padded', () {
        expect(calcPaddedLen(unpadded), padded);
      });
    }

    test('pads the longest plaintext to 2^32 bytes', () {
      expect(calcPaddedLen(0xffffffff), 0x100000000);
    });
  });

  group('unpad', () {
    test('rejects an extended prefix for fewer than 65536 bytes', () {
      final padded = Uint8List(6 + calcPaddedLen(65535))
        ..[4] = 0xff
        ..[5] = 0xff;

      expect(() => unpad(padded), throwsFormatException);
    });
  });

  group('encrypt and decrypt', () {
    for (final (i, v) in _cases(valid, 'encrypt_decrypt').indexed) {
      test('vector $i', () {
        final conversationKey = _bytes(v['conversation_key']);

        expect(
          Nip44.conversationKey(
            privateKey: v['sec1'],
            publicKey: _publicKey(v['sec2']),
          ),
          conversationKey,
        );
        expect(
          Nip44.conversationKey(
            privateKey: v['sec2'],
            publicKey: _publicKey(v['sec1']),
          ),
          conversationKey,
        );
        expect(
          Nip44.encrypt(
            v['plaintext'],
            conversationKey,
            nonce: _bytes(v['nonce']),
          ),
          v['payload'],
        );
        expect(Nip44.decrypt(v['payload'], conversationKey), v['plaintext']);
        expect(
          Nip44.decryptMessage(
            v['payload'],
            recipientPrivateKey: v['sec2'],
            senderPublicKey: _publicKey(v['sec1']),
          ),
          v['plaintext'],
        );
      });
    }

    for (final (i, v) in _cases(valid, 'encrypt_decrypt_long_msg').indexed) {
      test('long message $i', () {
        final conversationKey = _bytes(v['conversation_key']);
        final plaintext = (v['pattern'] as String) * (v['repeat'] as int);
        final payload = Nip44.encrypt(
          plaintext,
          conversationKey,
          nonce: _bytes(v['nonce']),
        );

        expect(_sha256(utf8.encode(plaintext)), v['plaintext_sha256']);
        expect(_sha256(utf8.encode(payload)), v['payload_sha256']);
        expect(Nip44.decrypt(payload, conversationKey), plaintext);
      });
    }

    // https://github.com/nostr-protocol/nips/blob/master/44.md#extended-length-prefix-test-vectors
    for (final (length, plaintextSha256, payloadSha256) in [
      (
        65535,
        '6e1bebca6a8229364a162a72ef064826c4cd7457bf54f190ef782bd9deff3e42',
        '6d8c2810d1e870fbaa1f0a0937126cca837a15f9260e27060c331d70a3c0bc84',
      ),
      (
        65536,
        'bf718b6f653bebc184e1479f1935b8da974d701b893afcf49e701f3e2f9f9c5a',
        'b7b4edb36ba92e267d322d56d9aebc22e7fa96ff52e3c12adc07f07a43cbc616',
      ),
      (
        65537,
        '008ffc88d3c96a9f307524eb361e47c5222a887fc45fa0c1fb8d429c5c23b430',
        'eeb7c7c5373894ea2c1547cfd3ccb15d5a0b2d619da852e5c79df792dcc9e435',
      ),
    ]) {
      test('message of $length bytes around the extended prefix', () {
        final conversationKey = _bytes(
          'c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d',
        );
        final plaintext = 'a' * length;
        final payload = Nip44.encrypt(
          plaintext,
          conversationKey,
          nonce: _bytes('${'0' * 63}1'),
        );

        expect(_sha256(utf8.encode(plaintext)), plaintextSha256);
        expect(_sha256(utf8.encode(payload)), payloadSha256);
        expect(Nip44.decrypt(payload, conversationKey), plaintext);
      });
    }

    // These vectors predate nostr-protocol/nips#1907, which made 65536 bytes and more valid.
    for (final length in (invalid['encrypt_msg_lengths'] as List).where(
      (length) => length < 65536,
    )) {
      test('rejects a plaintext of $length bytes', () {
        expect(
          () => Nip44.encrypt('a' * (length as int), Uint8List(32)),
          throwsArgumentError,
        );
      });
    }

    for (final (i, v) in _cases(invalid, 'decrypt').indexed) {
      test('rejects ${v['note']} (vector $i)', () {
        expect(
          () => Nip44.decrypt(v['payload'], _bytes(v['conversation_key'])),
          v['note'] == 'invalid MAC'
              ? throwsA(isA<Nip44InvalidMacException>())
              : throwsFormatException,
        );
      });
    }

    for (final (variant, rewrite) in [
      (
        'the URL-safe base64 alphabet',
        (String payload) => payload.replaceAll('+', '-').replaceAll('/', '_'),
      ),
      (
        'a percent-encoded base64 padding',
        (String payload) => payload.replaceAll('=', '%3D'),
      ),
    ]) {
      test('rejects $variant', () {
        final v = _cases(
          valid,
          'encrypt_decrypt',
        ).firstWhere((v) => rewrite(v['payload']) != v['payload']);

        expect(
          () => Nip44.decrypt(
            rewrite(v['payload']),
            _bytes(v['conversation_key']),
          ),
          throwsFormatException,
        );
      });
    }

    test('uses a fresh nonce on each message', () {
      final conversationKey = Uint8List(32);

      expect(
        Nip44.encrypt('hello', conversationKey),
        isNot(Nip44.encrypt('hello', conversationKey)),
      );
    });

    test('the recipient decrypts what the sender encrypts', () {
      const sender =
          '5c0c523f52a5b6fad39ed2403092df8cebc36318b39383bca6c00808626fab3a';
      const recipient =
          '4b22aa260e4acb7021e32f38a6cdf4b673c6a277755bfce287e370c924dc936d';

      final payload = Nip44.encryptMessage(
        'hello bob',
        senderPrivateKey: sender,
        recipientPublicKey: _publicKey(recipient),
      );

      expect(
        Nip44.decryptMessage(
          payload,
          recipientPrivateKey: recipient,
          senderPublicKey: _publicKey(sender),
        ),
        'hello bob',
      );
      expect(
        () => Nip44.decryptMessage(
          payload,
          recipientPrivateKey: sender,
          senderPublicKey: _publicKey(sender),
        ),
        throwsA(isA<Nip44InvalidMacException>()),
      );
    });
  });
}
