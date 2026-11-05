import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_pq/ndk_pq.dart';

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
