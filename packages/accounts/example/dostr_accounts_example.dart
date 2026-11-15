import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

Future<void> main() async {
  final accounts = Accounts(const Bip340SignerFactory());
  accounts.authStateChanges.listen(
    (account) => print('logged in: ${account?.pubkey}'),
  );

  final writer = Bip340.generatePrivateKey();
  final reader = Bip340.generatePrivateKey();
  accounts.loginPrivateKey(privkey: writer.privateKey!);
  accounts.loginPublicKey(pubkey: reader.publicKey);
  print('can sign as the read-only account? ${accounts.canSign}');

  accounts.switchAccount(pubkey: writer.publicKey);
  final signed = await accounts.sign(
    Nip01Event(
      pubkey: writer.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: [],
      content: 'hello',
    ),
  );
  print('signed ${signed.id}');

  await accounts.logout();
  await accounts.dispose();
}
