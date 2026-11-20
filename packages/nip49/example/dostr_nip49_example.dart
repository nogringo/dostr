import 'package:dostr_nip49/dostr_nip49.dart';

Future<void> main() async {
  const privateKey =
      '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683';

  final ncryptsec = await Ncryptsec.encrypt(
    privateKey,
    'password',
    keySecurity: Nip49KeySecurity.secure,
  );
  final encoded = ncryptsec.encode();
  print(encoded);

  final decoded = Ncryptsec.decode(encoded);
  print('logN ${decoded.logN}, key ${decoded.keySecurity.name}');
  print(await decoded.decrypt('password') == privateKey);
}
