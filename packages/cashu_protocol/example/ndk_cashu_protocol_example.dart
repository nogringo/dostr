import 'package:http/http.dart' as http;
import 'package:ndk_cashu_protocol/ndk_cashu_protocol.dart';
import 'package:ndk_http/ndk_http.dart';

/// The amount of a `cashuB` token that its mint still holds as unspent.
Future<int> unspentAmount(String encoded) async {
  final token = CashuTokenEncoder.decodedToken(encoded);
  if (token == null) throw FormatException('not a cashuB token', encoded);

  final client = http.Client();
  try {
    final states = await CashuRepoImpl(client: NdkHttp(client)).checkTokenState(
      mintUrl: token.mintUrl,
      proofPubkeys: token.proofs.map((proof) => proof.Y).toList(),
    );
    final unspent = {
      for (final state in states)
        if (state.state == CashuProofState.unspend) state.Y,
    };
    return CashuTools.sumOfProofs(
      proofs: token.proofs.where((proof) => unspent.contains(proof.Y)).toList(),
    );
  } finally {
    client.close();
  }
}
