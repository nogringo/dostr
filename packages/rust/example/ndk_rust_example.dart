import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_rust/ndk_rust.dart';

Future<void> main() async {
  final keyPair = Bip340.generatePrivateKey();
  final signer = Bip340EventSigner(
    privateKey: keyPair.privateKey,
    publicKey: keyPair.publicKey,
  );

  final event = await signer.sign(
    Nip01Event(pubKey: keyPair.publicKey, kind: 1, tags: [], content: 'hello'),
  );

  print(await RustEventVerifier().verify(event));
}
