import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

Future<void> main() async {
  final accounts = Accounts(const Bip340EventSignerFactory());
  accounts.authStateChanges.listen(
    (account) => print('logged in: ${account?.pubkey}'),
  );

  final writer = Bip340.generatePrivateKey();
  final reader = Bip340.generatePrivateKey();
  accounts.loginPrivateKey(
    pubkey: writer.publicKey,
    privkey: writer.privateKey!,
  );
  accounts.loginPublicKey(pubkey: reader.publicKey);
  print('can sign as the read-only account? ${accounts.canSign}');

  accounts.switchAccount(pubkey: writer.publicKey);
  final signed = await accounts.sign(
    Nip01Event(
      pubKey: writer.publicKey,
      kind: Nip01Event.kTextNoteKind,
      tags: [],
      content: 'hello',
    ),
  );
  print('signed ${signed.id}');

  accounts.logout();
  await accounts.dispose();
}
