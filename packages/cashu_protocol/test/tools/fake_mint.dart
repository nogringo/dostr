import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk_cashu_protocol/ndk_cashu_protocol.dart';

/// A mint whose private key for an amount is the amount + 1000.
class FakeMint {
  static BigInt key(int amount) => BigInt.from(amount + 1000);

  final keyset = CahsuKeyset(
    id: '00c726786980c4d9',
    mintUrl: 'https://mint.example',
    unit: 'sat',
    active: true,
    inputFeePPK: 0,
    mintKeyPairs: {
      for (final amount in [1, 2, 4, 8, 128])
        CahsuMintKeyPair(
          amount: amount,
          pubkey: CashuTools.ecPointToHex((CashuTools.getG() * key(amount))!),
        ),
    },
  );

  CashuBlindedMessageItem output(String secret, int amount) {
    final (blindedMessage, r) = CashuBdhke.blindMessage(secret);
    return CashuBlindedMessageItem(
      blindedMessage: CashuBlindedMessage(
        id: keyset.id,
        amount: amount,
        blindedMessage: blindedMessage,
      ),
      secret: secret,
      r: r,
      amount: amount,
    );
  }

  CashuBlindedSignature sign(CashuBlindedMessage output, int amount) =>
      CashuBlindedSignature(
        id: keyset.id,
        amount: amount,
        blindedSignature: CashuTools.ecPointToHex(
          (CashuTools.pointFromHexString(output.blindedMessage) * key(amount))!,
        ),
      );

  /// the C a valid proof of [secret] holds
  String expectedC(String secret, int amount) =>
      CashuTools.ecPointToHex((CashuTools.hashToCurve(secret) * key(amount))!);

  /// signs a swap's outputs in the order it gets them
  http.Client get client => MockClient((request) async {
    final outputs = (jsonDecode(request.body)['outputs'] as List<dynamic>).map(
      (output) => CashuBlindedMessage.fromServerMap(output as Map),
    );
    return http.Response(
      jsonEncode({
        'signatures': [
          for (final output in outputs)
            {
              'id': output.id,
              'amount': output.amount,
              'C_': sign(output, output.amount).blindedSignature,
            },
        ],
      }),
      200,
    );
  });
}
