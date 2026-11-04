import 'package:ndk_nip44/ndk_nip44.dart';

Future<void> main() async {
  const alicePrivateKey =
      '0000000000000000000000000000000000000000000000000000000000000001';
  const alicePublicKey =
      '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';
  const bobPrivateKey =
      '0000000000000000000000000000000000000000000000000000000000000002';
  const bobPublicKey =
      'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';

  final payload = await Nip44.encryptMessage(
    'hello bob',
    alicePrivateKey,
    bobPublicKey,
  );

  final plaintext = await Nip44.decryptMessage(
    payload,
    bobPrivateKey,
    alicePublicKey,
  );
  print(plaintext);
}
