import 'package:dostr_cashu_protocol/dostr_cashu_protocol.dart';
import 'package:dostr_secp256k1/dostr_secp256k1.dart';
import 'package:test/test.dart';

void main() {
  // https://github.com/cashubtc/nuts/blob/main/tests/20-test.md
  group('CashuTools.createMintSignature', () {
    const quote = '0192d3c0-7e8a-7c3d-8e9f-1a2b3c4d5e6f';
    final outputs = [
      CashuBlindedMessage(
        id: '009a1f293253e41e',
        amount: 1,
        blindedMessage:
            '036d6caac248af96f6afa7f904f550253a0f3ef3f5aa2fe6838a95b216691468e2',
      ),
      CashuBlindedMessage(
        id: '009a1f293253e41e',
        amount: 1,
        blindedMessage:
            '021f8a566c205633d029094747d2e18f44e05993dda7a5f88f496078205f656e59',
      ),
    ];
    final messageHash = CashuTools.hexToBytes(
      'c164fd384879f74ab6ea2e7cf13d90ed42e6df9d5de607eeb5c9cc7d36fb1c21',
    );
    final publicKey = CashuTools.hexToBytes(
      '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
    );

    test('signs the msg_to_sign of the vector', () {
      final signature = CashuTools.createMintSignature(
        quote: quote,
        blindedMessagesOutputs: outputs,
        privateKeyHex: '${'0' * 63}1',
      );

      expect(
        Schnorr.verify(
          messageHash,
          CashuTools.hexToBytes(signature),
          publicKey,
        ),
        isTrue,
      );
    });

    test('agrees with the signature of the vector', () {
      final signature = CashuTools.hexToBytes(
        '4881093a332ff7c79f3e598ce5b249d64978b47165a0b19c18adf0ced0246228'
        'e61e702f0abaf1bf27b92be4336bdbabacfbe4c914076386b3c66fdcd0b3480e',
      );

      expect(Schnorr.verify(messageHash, signature, publicKey), isTrue);
    });
  });
}
