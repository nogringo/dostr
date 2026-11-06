import 'package:ndk_nip07/ndk_nip07.dart';

Future<void> main() async {
  final signer = Nip07EventSigner();
  if (!signer.canSign()) {
    print('No NIP-07 extension in this browser');
    return;
  }

  final pubkey = await signer.getPublicKeyAsync();
  print(pubkey);
}
