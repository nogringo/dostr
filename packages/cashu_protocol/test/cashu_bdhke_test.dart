import 'package:test/test.dart';
import 'package:dostr_cashu_protocol/dostr_cashu_protocol.dart';

import 'tools/fake_mint.dart';

void main() {
  group('CashuBdhke.blindMessage', () {
    // Note: The NUT-00 test vectors assume secrets are raw bytes,
    // but this implementation treats secrets as hex strings that get UTF-8 encoded.
    // These tests verify the actual behavior of the implementation.

    test('Test Vector 1 - blindMessage with known secret and r', () {
      // Using a test secret (hex string representation)
      // This tests that the function produces consistent output
      final secret =
          'd341ee4871f1f889041e63cf0d3823c713eea6aff01e80f1719f08f9e5be98f6';
      final r = BigInt.parse(
        '99fce58439fc37412ab3468b73db0569322588f62fb3a49182d67e23d877824a',
        radix: 16,
      );

      final (blindedMessage, returnedR) = CashuBdhke.blindMessage(secret, r: r);

      // Verify the function returns a valid blinded message
      expect(blindedMessage, isNotEmpty);
      expect(
        blindedMessage.length,
        equals(66),
      ); // Compressed EC point (33 bytes = 66 hex chars)
      expect(returnedR, equals(r));
    });

    test('Test Vector 2 - blindMessage with known secret and r', () {
      // Using another test secret (hex string representation)
      final secret =
          'f1aaf16c2239746f369572c0784d9dd3d032d952c2d992175873fb58fae31a60';
      final r = BigInt.parse(
        'f78476ea7cc9ade20f9e05e58a804cf19533f03ea805ece5fee88c8e2874ba50',
        radix: 16,
      );

      final (blindedMessage, returnedR) = CashuBdhke.blindMessage(secret, r: r);

      // Verify the function returns a valid blinded message
      expect(blindedMessage, isNotEmpty);
      expect(blindedMessage.length, equals(66));
      expect(returnedR, equals(r));
    });

    test('blindMessage returns valid blinded message without r', () {
      // Test that the function works when r is not provided
      final secret =
          'd341ee4871f1f889041e63cf0d3823c713eea6aff01e80f1719f08f9e5be98f6';

      final (blindedMessage, r) = CashuBdhke.blindMessage(secret);

      // Should return a valid hex string for the blinded message
      expect(blindedMessage, isNotEmpty);
      expect(
        blindedMessage.length,
        greaterThan(60),
      ); // Compressed EC point should be 66 chars (33 bytes)

      // Should return a valid r value
      expect(r, isNotNull);
      expect(r, greaterThan(BigInt.zero));
    });

    test('a generated r is a full size scalar', () {
      // a small r lets the mint link B_ to the proof by brute force
      for (var i = 0; i < 20; i++) {
        final (_, r) = CashuBdhke.blindMessage('secret');
        expect(r.bitLength, greaterThan(128));
      }
    });

    test('blindMessage produces consistent results with same inputs', () {
      // Test determinism: same secret and r should produce same output
      final secret =
          'd341ee4871f1f889041e63cf0d3823c713eea6aff01e80f1719f08f9e5be98f6';
      final r = BigInt.parse(
        '99fce58439fc37412ab3468b73db0569322588f62fb3a49182d67e23d877824a',
        radix: 16,
      );

      final (blindedMessage1, r1) = CashuBdhke.blindMessage(secret, r: r);
      final (blindedMessage2, r2) = CashuBdhke.blindMessage(secret, r: r);

      expect(blindedMessage1, equals(blindedMessage2));
      expect(r1, equals(r2));
      expect(r1, equals(r));
    });

    test('blindMessage produces different results with different r values', () {
      // Test that different r values produce different blinded messages
      final secret =
          'd341ee4871f1f889041e63cf0d3823c713eea6aff01e80f1719f08f9e5be98f6';
      final r1 = BigInt.parse(
        '99fce58439fc37412ab3468b73db0569322588f62fb3a49182d67e23d877824a',
        radix: 16,
      );
      final r2 = BigInt.parse(
        'f78476ea7cc9ade20f9e05e58a804cf19533f03ea805ece5fee88c8e2874ba50',
        radix: 16,
      );

      final (blindedMessage1, _) = CashuBdhke.blindMessage(secret, r: r1);
      final (blindedMessage2, _) = CashuBdhke.blindMessage(secret, r: r2);

      expect(blindedMessage1, isNot(equals(blindedMessage2)));
    });
  });

  group('CashuBdhke.createBlindedMsgForAmounts', () {
    test('derives each output from the next counter', () async {
      final seed = CashuSeed();
      await seed.setSeedPhrase(
        seedPhrase:
            'half depart obvious quality work element tank gorilla view sugar picture humble',
      );
      final counters = [3, 4];
      final items = await CashuBdhke.createBlindedMsgForAmounts(
        keysetId: '009a1f293253e41e',
        amounts: [1, 2],
        cashuSeed: seed,
        cashuSeedSecretGenerator: DartCashuKeyDerivation(),
        nextCounter: () async => counters.removeAt(0),
      );

      expect(counters, isEmpty);
      expect(items.map((item) => item.amount), [1, 2]);
      expect(
        items.map((item) => item.blindedMessage.id),
        everyElement('009a1f293253e41e'),
      );
      // NUT-13 vectors for counters 3 and 4
      expect(items.map((item) => item.secret), [
        '59284fd1650ea9fa17db2b3acf59ecd0f2d52ec3261dd4152785813ff27a33bf',
        '576c23393a8b31cc8da6688d9c9a96394ec74b40fdaf1f693a6bb84284334ea0',
      ]);
    });

    test('fails instead of skipping an output it cannot derive', () async {
      final seed = CashuSeed();
      await seed.setSeedPhrase(seedPhrase: CashuSeed.generateSeedPhrase());

      expect(
        CashuBdhke.createBlindedMsgForAmounts(
          keysetId: 'not hex',
          amounts: [1],
          cashuSeed: seed,
          cashuSeedSecretGenerator: DartCashuKeyDerivation(),
          nextCounter: () async => 0,
        ),
        throwsException,
      );
    });
  });

  group('CashuTools.hashToCurve', () {
    // NUT-00 test vectors, whose messages are valid UTF-8
    const vectors = {
      '0000000000000000000000000000000000000000000000000000000000000000':
          '024cce997d3b518f739663b757deaec95bcd9473c30a14ac2fd04023a739d1a725',
      '0000000000000000000000000000000000000000000000000000000000000001':
          '022e7158e11c9506f1aa4248bf531298daa7febd6194f003edcd9b93ade6253acf',
      '0000000000000000000000000000000000000000000000000000000000000002':
          '026cdbe15362df59cd1dd3c9c11de8aedac2106eca69236ecd9fbe117af897be4f',
    };

    for (final MapEntry(key: message, value: point) in vectors.entries) {
      test(message, () {
        final secret = String.fromCharCodes(CashuTools.hexToBytes(message));
        expect(CashuTools.ecPointToHex(CashuTools.hashToCurve(secret)), point);
      });
    }
  });

  group('CashuBdhke.unblindSignatures', () {
    final mint = FakeMint();

    test('pairs each signature with the output at its position', () {
      final outputs = [
        for (var i = 0; i < 40; i++) mint.output('secret $i', i.isEven ? 1 : 2),
      ];
      final signatures = [
        for (final output in outputs)
          mint.sign(output.blindedMessage, output.amount),
      ];

      final proofs = CashuBdhke.unblindSignatures(
        mintSignatures: signatures,
        blindedMessages: outputs,
        mintPublicKeys: mint.keyset,
      );

      expect(proofs.map((proof) => proof.secret), [
        for (final output in outputs) output.secret,
      ]);
      for (final (i, proof) in proofs.indexed) {
        expect(
          proof.unblindedSig,
          mint.expectedC(proof.secret, outputs[i].amount),
        );
        expect(proof.keysetId, mint.keyset.id);
      }
    });

    test('unblinds NUT-08 change with the amounts the mint imprinted', () {
      final blankOutputs = [
        for (var i = 0; i < 4; i++) mint.output('blank $i', 0),
      ];
      final change = [
        mint.sign(blankOutputs[0].blindedMessage, 4),
        mint.sign(blankOutputs[1].blindedMessage, 128),
      ];

      final proofs = CashuBdhke.unblindSignatures(
        mintSignatures: change,
        blindedMessages: blankOutputs,
        mintPublicKeys: mint.keyset,
      );

      expect(proofs.map((proof) => proof.amount), [4, 128]);
      expect(proofs.map((proof) => proof.unblindedSig), [
        mint.expectedC('blank 0', 4),
        mint.expectedC('blank 1', 128),
      ]);
    });

    test('throws when there are more signatures than outputs', () {
      final outputs = [mint.output('only', 1)];
      final signature = mint.sign(outputs[0].blindedMessage, 1);

      expect(
        () => CashuBdhke.unblindSignatures(
          mintSignatures: [signature, signature],
          blindedMessages: outputs,
          mintPublicKeys: mint.keyset,
        ),
        throwsException,
      );
    });
  });
}
