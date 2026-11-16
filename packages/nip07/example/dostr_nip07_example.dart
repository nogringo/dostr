import 'package:dostr_nip07/dostr_nip07.dart';

Future<void> main() async {
  if (!Nip07Signer.isAvailable) {
    print('No NIP-07 extension in this browser');
    return;
  }

  final signer = await Nip07Signer.connect();
  print(signer.publicKey);
}
