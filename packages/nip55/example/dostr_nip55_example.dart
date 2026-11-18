import 'package:dostr_nip55/dostr_nip55.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const signerApp = Nip55SignerApp();
  if (!await signerApp.isAppInstalled()) {
    debugPrint('No NIP-55 signer app installed');
    return;
  }

  final Nip55LoginResult login;
  try {
    login = await signerApp.login();
  } on SignerRequestRejectedException {
    debugPrint('The user refused to log in');
    return;
  }

  final signer = Nip55Signer(
    publicKey: login.pubkey,
    signerApp: Nip55SignerApp(package: login.package),
  );
  debugPrint(signer.publicKey);
}
