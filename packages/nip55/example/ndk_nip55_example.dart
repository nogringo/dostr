import 'package:flutter/widgets.dart';
import 'package:ndk_nip55/ndk_nip55.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const nip55Signer = Nip55Signer();
  if (!await nip55Signer.isAppInstalled()) {
    debugPrint('No NIP-55 signer app installed');
    return;
  }

  final login = await nip55Signer.login();
  if (login == null) return;

  final signer = Nip55EventSigner(
    publicKey: login.pubkey,
    nip55Signer: Nip55Signer(package: login.package),
  );
  debugPrint(signer.getPublicKey());
}
