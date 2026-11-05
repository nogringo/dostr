import 'package:ndk_nip49/ndk_nip49.dart';

Future<void> main() async {
  const privateKey =
      '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683';

  final ncryptsec = await Nip49.encrypt(
    privateKey,
    'password',
    keySecurity: Nip49KeySecurity.secure,
  );
  print(ncryptsec);

  final decrypted = await Nip49.decrypt(ncryptsec, 'password');
  print(decrypted == privateKey);
}
