import 'dart:convert';

import 'package:ndk_nip44/ndk_nip44.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:test/test.dart';

String xOnlyPublicKeyHex(String privateKeyHex) {
  final point = ECCurve_secp256k1().G * BigInt.parse(privateKeyHex, radix: 16);
  return point!.x!.toBigInteger()!.toRadixString(16).padLeft(64, '0');
}

void main() {
  const priv =
      'fb505c65d4df950f5d28c9e4d285ee12ffaf315deef1fc24e3c7cd1e7e35f2b1';
  const pub =
      'b1a5c93edcc8d586566fde53a20bdb50049a97b15483cb763854e57016e0fa3d';

  test('decrypts a known payload', () {
    const ciphertext =
        'VezuSvWak++ASjFMRqBPWS3mK5pZ0vRLL325iuIL4S+r8n9z+DuMau5vMElz1tGC/UqCDmbzE2kwplafaFo/FnIZMdEj4pdxgptyBV1ifZpH3TEF6OMjEtqbYRRqnxgIXsuOSXaerWgpi0pm+raHQPseoELQI/SZ1cvtFqEUCXdXpa5AYaSd+quEuthAEw7V1jP+5TDRCEC8jiLosBVhCtaPpLcrm8HydMYJ2XB6Ixs=?iv=/rtV49RFm0XyFEwG62Eo9A==';

    expect(json.decode(Nip04.decrypt(priv, pub, ciphertext)), [
      ['p', '9ec7a778167afb1d30c4833de9322da0c08ba71a69e1911d5578d3144bb56437'],
      ['p', '8c0da4862130283ff9e67d889df264177a508974e2feb96de139804ea66d6168'],
    ]);
  });

  test('the recipient decrypts what the sender encrypts', () {
    const senderPriv =
        '0000000000000000000000000000000000000000000000000000000000000001';
    const recipientPriv =
        '0000000000000000000000000000000000000000000000000000000000000002';

    final encrypted = Nip04.encrypt(
      senderPriv,
      xOnlyPublicKeyHex(recipientPriv),
      'some content',
    );

    expect(
      Nip04.decrypt(recipientPriv, xOnlyPublicKeyHex(senderPriv), encrypted),
      'some content',
    );
  });
}
