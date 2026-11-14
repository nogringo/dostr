import 'dart:convert';

import 'package:bech32/bech32.dart';
import 'package:convert/convert.dart';
import 'package:dostr_nip49/dostr_nip49.dart';
import 'package:dostr_nip49/src/convert_bits.dart';
import 'package:dostr_nip49/src/scrypt.dart';
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

  const vector =
      'ncryptsec1qgg9947rlpvqu76pj5ecreduf9jxhselq2nae2kghhvd5g7dgjtcxfqtd67p9m0w57lspw8gsq6yphnm8623nsl8xn9j4jdzz84zm3frztj3z7s35vpzmqf6ksu8r89qk5z2zxfmu5gv8th8wclt0h4p';

  List<int> payloadOf(String ncryptsec) => convertBits(
    Bech32Decoder().convert(ncryptsec, ncryptsec.length).data,
    5,
    8,
    pad: false,
  );

  String encode(List<int> payload, {String hrp = 'ncryptsec'}) {
    final data = convertBits(payload, 8, 5, pad: true);
    return Bech32Encoder().convert(
      Bech32(hrp, data),
      hrp.length + data.length + 7,
    );
  }

  Matcher throwsFormatMessage(String message) => throwsA(
    isA<FormatException>().having((e) => e.message, 'message', message),
  );

  final throwsWrongPassword = throwsA(isA<Nip49WrongPasswordException>());

  group('test vector', () {
    test('is a 91 byte version 2 payload at log_n 16, key insecure', () {
      final payload = payloadOf(vector);

      expect(payload, hasLength(91));
      expect(payload[0], 0x02);
      expect(payload[1], 16);
      expect(payload[42], Nip49KeySecurity.insecure.value);
    });

    test('decrypts with the password typed in fullwidth forms', () async {
      expect(await Nip49.decrypt(vector, 'ｎｏｓｔｒ'), privateKey);
    });
  });

  group('encrypt', () {
    for (final keySecurity in Nip49KeySecurity.values) {
      test('writes the ${keySecurity.name} key security byte', () async {
        final ncryptsec = await Nip49.encrypt(
          privateKey,
          'password',
          logN: 3,
          keySecurity: keySecurity,
        );
        final payload = payloadOf(ncryptsec);

        expect(ncryptsec, hasLength(vector.length));
        expect(payload, hasLength(91));
        expect(payload[0], 0x02);
        expect(payload[1], 3);
        expect(payload[42], keySecurity.value);
        expect(await Nip49.decrypt(ncryptsec, 'password'), privateKey);
      });
    }

    test('marks the key security as unknown by default', () async {
      final ncryptsec = await Nip49.encrypt(privateKey, 'password', logN: 3);

      expect(payloadOf(ncryptsec)[42], 0x02);
    });

    for (final logN in [1, 4, 8, 12]) {
      test('round trips at log_n $logN', () async {
        final ncryptsec = await Nip49.encrypt(
          privateKey,
          'password',
          logN: logN,
        );

        expect(payloadOf(ncryptsec)[1], logN);
        expect(await Nip49.decrypt(ncryptsec, 'password'), privateKey);
      });
    }

    test('draws a fresh salt and nonce every time', () async {
      final first = await Nip49.encrypt(privateKey, 'password', logN: 3);
      final second = await Nip49.encrypt(privateKey, 'password', logN: 3);
      final firstPayload = payloadOf(first);
      final secondPayload = payloadOf(second);

      expect(first, isNot(second));
      expect(firstPayload.sublist(2, 18), isNot(secondPayload.sublist(2, 18)));
      expect(
        firstPayload.sublist(18, 42),
        isNot(secondPayload.sublist(18, 42)),
      );
      expect(await Nip49.decrypt(second, 'password'), privateKey);
    });

    test('round trips with an empty password', () async {
      final ncryptsec = await Nip49.encrypt(privateKey, '', logN: 3);

      expect(await Nip49.decrypt(ncryptsec, ''), privateKey);
      expect(Nip49.decrypt(ncryptsec, ' '), throwsWrongPassword);
    });

    test('accepts an uppercase hex key and decrypts it lowercase', () async {
      final ncryptsec = await Nip49.encrypt(
        privateKey.toUpperCase(),
        'password',
        logN: 3,
      );

      expect(await Nip49.decrypt(ncryptsec, 'password'), privateKey);
    });

    test('rejects a private key that is not 32 bytes', () {
      expect(
        Nip49.encrypt(privateKey.substring(2), 'password', logN: 3),
        throwsArgumentError,
      );
      expect(
        Nip49.encrypt('${privateKey}00', 'password', logN: 3),
        throwsArgumentError,
      );
    });

    test('rejects a private key that is not hex', () {
      expect(
        Nip49.encrypt('${privateKey.substring(1)}g', 'password', logN: 3),
        throwsFormatException,
      );
      expect(
        Nip49.encrypt(privateKey.substring(1), 'password', logN: 3),
        throwsFormatException,
      );
    });

    test('rejects a log_n outside 1 to maxLogN', () {
      expect(
        Nip49.encrypt(privateKey, 'password', logN: 0),
        throwsA(isA<RangeError>()),
      );
      expect(
        Nip49.encrypt(privateKey, 'password', logN: Nip49.maxLogN + 1),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('decrypt', () {
    late String ncryptsec;
    late List<int> payload;

    setUpAll(() async {
      ncryptsec = await Nip49.encrypt(privateKey, 'password', logN: 4);
      payload = payloadOf(ncryptsec);
    });

    test('accepts an all uppercase ncryptsec', () async {
      expect(
        await Nip49.decrypt(ncryptsec.toUpperCase(), 'password'),
        privateKey,
      );
    });

    test('accepts a log_n equal to maxLogN', () async {
      expect(
        await Nip49.decrypt(ncryptsec, 'password', maxLogN: 4),
        privateKey,
      );
    });

    test('rejects a log_n of 0', () {
      expect(
        Nip49.decrypt(encode([...payload]..[1] = 0), 'password'),
        throwsA(isA<RangeError>()),
      );
    });

    test('rejects a huge log_n without deriving a key', () {
      for (final logN in [Nip49.maxLogN + 1, 255]) {
        expect(
          Nip49.decrypt(encode([...payload]..[1] = logN), 'password'),
          throwsA(isA<RangeError>()),
        );
      }
    });

    test('rejects a wrong password', () {
      expect(Nip49.decrypt(ncryptsec, 'Password'), throwsWrongPassword);
      expect(Nip49.decrypt(ncryptsec, 'password '), throwsWrongPassword);
    });

    test('rejects an unsupported version', () {
      for (final version in [0x00, 0x01, 0x03]) {
        expect(
          Nip49.decrypt(encode([...payload]..[0] = version), 'password'),
          throwsFormatMessage('Unsupported ncryptsec'),
        );
      }
    });

    test('rejects a payload that is not 91 bytes', () {
      expect(
        Nip49.decrypt(encode(payload.sublist(0, 90)), 'password'),
        throwsFormatMessage('Unsupported ncryptsec'),
      );
      expect(
        Nip49.decrypt(encode([...payload, 0]), 'password'),
        throwsFormatMessage('Unsupported ncryptsec'),
      );
      expect(
        Nip49.decrypt(encode([]), 'password'),
        throwsFormatMessage('Unsupported ncryptsec'),
      );
    });

    test('rejects a truncated string', () {
      for (final length in [ncryptsec.length - 1, 100, 20]) {
        expect(
          Nip49.decrypt(ncryptsec.substring(0, length), 'password'),
          throwsFormatMessage('Not a valid bech32 string'),
        );
      }
    });

    test('rejects malformed strings', () {
      final malformed = [
        '',
        'ncryptsec',
        'ncryptsec1',
        'N${ncryptsec.substring(1)}',
        '${ncryptsec.substring(0, 40)}b${ncryptsec.substring(41)}',
        ' $ncryptsec',
        '$ncryptsec\n',
      ];
      for (final input in malformed) {
        expect(
          Nip49.decrypt(input, 'password'),
          throwsFormatMessage('Not a valid bech32 string'),
        );
      }
    });

    test('rejects another bech32 prefix', () {
      for (final hrp in ['nsec', 'ncrypt', 'ncryptsec2']) {
        expect(
          Nip49.decrypt(encode(payload, hrp: hrp), 'password'),
          throwsFormatMessage('Not an ncryptsec'),
        );
      }
    });

    test('authenticates the key security byte', () {
      expect(
        Nip49.decrypt(encode([...payload]..[42] = 0x01), 'password'),
        throwsWrongPassword,
      );
    });

    test('detects a change to the log_n, salt, nonce, ciphertext or mac', () {
      final tampered = {
        'log_n': 1,
        'salt': 2,
        'nonce': 41,
        'ciphertext': 43,
        'mac': 90,
      };
      for (final MapEntry(key: part, value: index) in tampered.entries) {
        final changed = [...payload];
        changed[index] ^= 0x01;
        expect(
          Nip49.decrypt(encode(changed), 'password'),
          throwsWrongPassword,
          reason: part,
        );
      }
    });
  });

  group('password normalization', () {
    test('matches the NFKC form of the spec example both ways', () async {
      const input = 'ÅΩẛ̣';
      const normalized = 'ÅΩṩ';

      final fromNormalized = await Nip49.encrypt(
        privateKey,
        normalized,
        logN: 3,
      );
      expect(await Nip49.decrypt(fromNormalized, input), privateKey);

      final fromInput = await Nip49.encrypt(privateKey, input, logN: 3);
      expect(await Nip49.decrypt(fromInput, normalized), privateKey);
    });

    test('treats decomposed and composed accents as one password', () async {
      final ncryptsec = await Nip49.encrypt(privateKey, 'café', logN: 3);

      expect(await Nip49.decrypt(ncryptsec, 'café'), privateKey);
    });

    test('folds compatibility characters', () async {
      final ncryptsec = await Nip49.encrypt(privateKey, 'ﬁle', logN: 3);

      expect(await Nip49.decrypt(ncryptsec, 'file'), privateKey);
    });

    test('keeps distinct characters distinct', () async {
      final ncryptsec = await Nip49.encrypt(privateKey, 'Å', logN: 3);

      expect(Nip49.decrypt(ncryptsec, 'A'), throwsWrongPassword);
      expect(Nip49.decrypt(ncryptsec, 'å'), throwsWrongPassword);
    });
  });
}
