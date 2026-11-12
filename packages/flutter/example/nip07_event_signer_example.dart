import 'package:dostr_flutter/dostr_flutter.dart';

void main() async {
  final signer = Nip07EventSigner();
  if (!signer.canSign()) {
    return;
  }

  final pubkey = await signer.getPublicKeyAsync();
  print(pubkey);
}
