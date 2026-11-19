import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_noble/dostr_noble.dart';

Future<void> main() async {
  final signer = const WebSignerFactory().createWithNewKeyPair();

  final event = await signer.sign(
    Nip01Event(
      pubkey: signer.publicKey,
      kind: 1,
      tags: [],
      content: 'hello nostr',
    ),
  );

  final valid = await WebEventVerifier().verify(event);
  print('${event.id} signed, valid: $valid');

  await signer.dispose();
}
