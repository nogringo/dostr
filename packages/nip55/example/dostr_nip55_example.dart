import 'package:dostr_nip55/dostr_nip55.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const signerApp = Nip55SignerApp();
  if (!await signerApp.isAppInstalled()) {
    debugPrint('No NIP-55 signer app installed');
    return;
  }

  final login = await signerApp.login();
  if (login == null) return;

  final signer = Nip55Signer(
    publicKey: login.pubkey,
    signerApp: Nip55SignerApp(package: login.package),
  );
  debugPrint(signer.getPublicKey());
}
