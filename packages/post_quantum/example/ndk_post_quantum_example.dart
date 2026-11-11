import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_post_quantum/ndk_post_quantum.dart';

Future<void> main() async {
  final keypair = QsRustEventSigner.generateKeypair(level: 87);
  final signer = QsRustEventSigner(keypair: keypair, level: 87);

  final event = await signer.sign(
    Nip01Event(
      pubKey: keypair.publicKeyHex,
      kind: 1,
      tags: [],
      content: 'hello',
    ),
  );

  print(await QsRustEventVerifier(level: 87).verify(event));
}
