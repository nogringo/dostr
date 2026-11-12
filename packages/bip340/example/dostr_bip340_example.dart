import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

Future<void> main() async {
  final signer = Bip340EventSignerFactory().createWithNewKeyPair();

  final event = await signer.sign(
    Nip01Event(
      pubKey: signer.getPublicKey(),
      kind: 1,
      tags: [],
      content: 'hello nostr',
    ),
  );

  final valid = await Bip340EventVerifier().verify(event);
  print('${event.id} signed, valid: $valid');

  await signer.dispose();
}
