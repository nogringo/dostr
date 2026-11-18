import 'package:dostr_nip07/dostr_nip07.dart';

Future<void> main() async {
  if (!await Nip07Signer.waitForExtension()) {
    print('No NIP-07 extension in this browser');
    return;
  }

  final signer = await Nip07Signer.connect();
  print(signer.publicKey);
}
