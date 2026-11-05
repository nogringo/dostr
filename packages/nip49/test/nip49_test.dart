import 'dart:convert';

import 'package:bech32/bech32.dart';
import 'package:convert/convert.dart';
import 'package:ndk_nip49/ndk_nip49.dart';
import 'package:ndk_nip49/src/convert_bits.dart';
import 'package:ndk_nip49/src/scrypt.dart';
import 'package:test/test.dart';

void main() {
  const privateKey =
      '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683';

  test('decrypts the NIP-49 test vector', () async {
    const ncryptsec =
        'ncryptsec1qgg9947rlpvqu76pj5ecreduf9jxhselq2nae2kghhvd5g7dgjtcxfqtd67p9m0w57lspw8gsq6yphnm8623nsl8xn9j4jdzz84zm3frztj3z7s35vpzmqf6ksu8r89qk5z2zxfmu5gv8th8wclt0h4p';

    expect(await Nip49.decrypt(ncryptsec, 'nostr'), privateKey);
  });

  test('round trips a private key', () async {
    final ncryptsec = await Nip49.encrypt(
      privateKey,
      'password',
      logN: 8,
      keySecurity: Nip49KeySecurity.secure,
    );

    expect(ncryptsec, startsWith('ncryptsec1'));
    expect(await Nip49.decrypt(ncryptsec, 'password'), privateKey);
  });

  test('rejects a wrong password', () async {
    final ncryptsec = await Nip49.encrypt(privateKey, 'password', logN: 8);

    expect(
      Nip49.decrypt(ncryptsec, 'wrong'),
      throwsA(isA<Nip49WrongPasswordException>()),
    );
  });

  test('normalizes the password to NFKC', () async {
    final ncryptsec = await Nip49.encrypt(privateKey, 'ÅΩẛ̣', logN: 8);

    expect(await Nip49.decrypt(ncryptsec, 'ÅΩṩ'), privateKey);
  });

  test('rejects a string that is not an ncryptsec', () {
    const nsec =
        'nsec1x5q52sf4q9z5zdgpg4qn2q298lhmqg38u3y72l856w3uupfhs6ps7q0j4y';

    expect(Nip49.decrypt(nsec, 'password'), throwsA(isA<FormatException>()));
  });

  test('rejects a string with a bad bech32 checksum', () async {
    final ncryptsec = await Nip49.encrypt(privateKey, 'password', logN: 8);
    final last = ncryptsec[ncryptsec.length - 1];
    final broken =
        ncryptsec.substring(0, ncryptsec.length - 1) +
        (last == 'q' ? 'p' : 'q');

    expect(Nip49.decrypt(broken, 'password'), throwsA(isA<FormatException>()));
  });

  test('rejects a logN above maxLogN', () async {
    final ncryptsec = await Nip49.encrypt(privateKey, 'password', logN: 9);

    expect(
      Nip49.decrypt(ncryptsec, 'password', maxLogN: 8),
      throwsA(isA<RangeError>()),
    );
  });

  test('rejects an unknown key security byte', () async {
    final ncryptsec = await Nip49.encrypt(privateKey, 'password', logN: 8);
    final decoded = Bech32Decoder().convert(ncryptsec, ncryptsec.length);
    final payload = convertBits(decoded.data, 5, 8, pad: false)..[42] = 0x03;
    final tampered = Bech32Encoder().convert(
      Bech32(decoded.hrp, convertBits(payload, 8, 5, pad: true)),
      ncryptsec.length,
    );

    expect(
      Nip49.decrypt(tampered, 'password'),
      throwsA(isA<FormatException>()),
    );
  });

  test('scrypt matches the RFC 7914 test vectors', () {
    expect(
      hex.encode(
        scrypt(
          utf8.encode('password'),
          utf8.encode('NaCl'),
          n: 1024,
          r: 8,
          p: 16,
          dkLen: 64,
        ),
      ),
      'fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640',
    );
    expect(
      hex.encode(
        scrypt(
          utf8.encode('pleaseletmein'),
          utf8.encode('SodiumChloride'),
          n: 16384,
          r: 8,
          p: 1,
          dkLen: 64,
        ),
      ),
      '7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2d5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887',
    );
  });
}
