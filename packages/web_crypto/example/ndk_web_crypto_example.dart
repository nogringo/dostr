import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_web_crypto/ndk_web_crypto.dart';

Future<void> main() async {
  final signer = const WebEventSignerFactory().createWithNewKeyPair();

  final event = await signer.sign(
    Nip01Event(
      pubKey: signer.getPublicKey(),
      kind: 1,
      tags: [],
      content: 'hello nostr',
    ),
  );

  final valid = await WebEventVerifier().verify(event);
  print('${event.id} signed, valid: $valid');

  await signer.dispose();
}
