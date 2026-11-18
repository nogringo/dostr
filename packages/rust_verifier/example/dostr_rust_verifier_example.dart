import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_rust_verifier/dostr_rust_verifier.dart';

Future<void> main() async {
  final keyPair = Bip340.generateKeyPair();
  final signer = Bip340Signer(keyPair.privateKey);

  final event = await signer.sign(
    Nip01Event(pubkey: keyPair.publicKey, kind: 1, tags: [], content: 'hello'),
  );

  print(await RustEventVerifier().verify(event));
}
