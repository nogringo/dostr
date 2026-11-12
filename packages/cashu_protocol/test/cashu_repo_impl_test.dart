import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk_cashu_protocol/ndk_cashu_protocol.dart';
import 'package:test/test.dart';

import 'tools/fake_mint.dart';

void main() {
  test('swap sends the outputs in the order it gets them', () async {
    late List<dynamic> sentOutputs;
    final mint = CashuRepoImpl(
      client: MockClient((request) async {
        sentOutputs = jsonDecode(request.body)['outputs'] as List<dynamic>;
        return http.Response(
          jsonEncode({
            'signatures': [
              for (final output in sentOutputs)
                {'id': output['id'], 'amount': output['amount'], 'C_': '02'},
            ],
          }),
          200,
        );
      }),
    );
    final outputs = [
      for (final (amount, b) in [(4, '02aa'), (1, '02bb'), (2, '02cc')])
        CashuBlindedMessage(id: '00ab', amount: amount, blindedMessage: b),
    ];

    final signatures = await mint.swap(
      mintUrl: 'https://mint.example',
      proofs: [],
      outputs: outputs,
    );

    expect(sentOutputs.map((output) => output['B_']), ['02aa', '02bb', '02cc']);
    expect(outputs.map((output) => output.amount), [4, 1, 2]);
    expect(signatures.map((signature) => signature.amount), [4, 1, 2]);
  });

  test(
    'a swap of many outputs of the same amount unblinds to valid proofs',
    () async {
      final fakeMint = FakeMint();
      // sorted by amount, as NUT-03 asks: the signatures come back in this order
      final outputs = [
        for (var i = 0; i < 40; i++)
          fakeMint.output('secret $i', i < 20 ? 1 : 2),
      ];

      final signatures = await CashuRepoImpl(client: fakeMint.client).swap(
        mintUrl: fakeMint.keyset.mintUrl,
        proofs: [],
        outputs: outputs.map((output) => output.blindedMessage).toList(),
      );
      final proofs = CashuBdhke.unblindSignatures(
        mintSignatures: signatures,
        blindedMessages: outputs,
        mintPublicKeys: fakeMint.keyset,
      );

      for (final proof in proofs) {
        expect(
          proof.unblindedSig,
          fakeMint.expectedC(proof.secret, proof.amount),
        );
      }
    },
  );
}
