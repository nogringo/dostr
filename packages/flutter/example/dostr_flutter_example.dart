import 'package:dostr_flutter/dostr_flutter.dart';

void main() async {
  if (!Nip07Signer.isAvailable) {
    return;
  }

  final signer = await Nip07Signer.connect();
  print(signer.publicKey);
}
