import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';

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
