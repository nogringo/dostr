import 'dart:convert';

import 'package:dostr_nip49/dostr_nip49.dart';
import 'package:dostr_nip49/src/bech32.dart';
import 'package:dostr_nip49/src/hex.dart';
import 'package:dostr_nip49/src/scrypt.dart';
import 'package:test/test.dart';

void main() {
  const privateKey =
      '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683';
  const nsec =
      'nsec1x5q52sf4q9z5zdgpg4qn2q298lhmqg38u3y72l856w3uupfhs6ps7q0j4y';
  const vector =
      'ncryptsec1qgg9947rlpvqu76pj5ecreduf9jxhselq2nae2kghhvd5g7dgjtcxfqtd67p9m0w57lspw8gsq6yphnm8623nsl8xn9j4jdzz84zm3frztj3z7s35vpzmqf6ksu8r89qk5z2zxfmu5gv8th8wclt0h4p';

  List<int> payloadOf(Ncryptsec ncryptsec) =>
      decodeBech32(ncryptsec.encode()).$2;

  Ncryptsec decodePayload(List<int> payload) =>
      Ncryptsec.decode(encodeBech32(Ncryptsec.prefix, payload));

  Matcher throwsFormatMessage(String message) => throwsA(
    isA<FormatException>().having((e) => e.message, 'message', message),
  );

  final throwsWrongPassword = throwsA(isA<Nip49WrongPasswordException>());

  test('scrypt matches the RFC 7914 test vectors', () {
    expect(
      bytesToHex(
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
      bytesToHex(
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

  group('test vector', () {
    test('decrypts with the password of NIP-49', () async {
      expect(await Ncryptsec.decode(vector).decrypt('nostr'), privateKey);
    });

    test('decrypts with the password typed in fullwidth forms', () async {
      expect(await Ncryptsec.decode(vector).decrypt('ｎｏｓｔｒ'), privateKey);
    });

    test('reads log_n 16 and an insecure key without the password', () {
      final ncryptsec = Ncryptsec.decode(vector);

      expect(ncryptsec.logN, 16);
      expect(ncryptsec.keySecurity, Nip49KeySecurity.insecure);
    });

    test('encodes back to the same string', () {
      expect(Ncryptsec.decode(vector).encode(), vector);
    });
  });

  group('encrypt', () {
    for (final keySecurity in Nip49KeySecurity.values) {
      test('writes the ${keySecurity.name} key security byte', () async {
        final ncryptsec = await Ncryptsec.encrypt(
          privateKey,
          'password',
          logN: 3,
          keySecurity: keySecurity,
        );
        final payload = payloadOf(ncryptsec);

        expect(ncryptsec.encode(), hasLength(vector.length));
        expect(payload, hasLength(91));
        expect(payload[0], 0x02);
        expect(payload[1], 3);
        expect(payload[42], keySecurity.value);
        expect(ncryptsec.keySecurity, keySecurity);
        expect(await ncryptsec.decrypt('password'), privateKey);
      });
    }

    test('marks the key security as unknown by default', () async {
      final ncryptsec = await Ncryptsec.encrypt(
        privateKey,
        'password',
        logN: 3,
      );

      expect(ncryptsec.keySecurity, Nip49KeySecurity.unknown);
    });

    for (final logN in [1, 4, 8, 12]) {
      test('round trips at log_n $logN', () async {
        final ncryptsec = await Ncryptsec.encrypt(
          privateKey,
          'password',
          logN: logN,
        );
        final decoded = Ncryptsec.decode(ncryptsec.encode());

        expect(decoded.logN, logN);
        expect(await decoded.decrypt('password'), privateKey);
      });
    }

    test('draws a fresh salt and nonce every time', () async {
      final first = await Ncryptsec.encrypt(privateKey, 'password', logN: 3);
      final second = await Ncryptsec.encrypt(privateKey, 'password', logN: 3);
      final firstPayload = payloadOf(first);
      final secondPayload = payloadOf(second);

      expect(first, isNot(second));
      expect(firstPayload.sublist(2, 18), isNot(secondPayload.sublist(2, 18)));
      expect(
        firstPayload.sublist(18, 42),
        isNot(secondPayload.sublist(18, 42)),
      );
      expect(await second.decrypt('password'), privateKey);
    });

    test('round trips with an empty password', () async {
      final ncryptsec = await Ncryptsec.encrypt(privateKey, '', logN: 3);

      expect(await ncryptsec.decrypt(''), privateKey);
      expect(ncryptsec.decrypt(' '), throwsWrongPassword);
    });

    test('accepts an uppercase hex key and decrypts it lowercase', () async {
      final ncryptsec = await Ncryptsec.encrypt(
        privateKey.toUpperCase(),
        'password',
        logN: 3,
      );

      expect(await ncryptsec.decrypt('password'), privateKey);
    });

    test('rejects a private key that is not 32 bytes of hex', () {
      for (final key in [
        privateKey.substring(2),
        '${privateKey}00',
        '${privateKey.substring(1)}g',
        privateKey.substring(1),
        nsec,
      ]) {
        expect(
          Ncryptsec.encrypt(key, 'password', logN: 3),
          throwsArgumentError,
        );
      }
    });

    test('never quotes the private key in its error', () async {
      for (final key in ['${privateKey}00', '${privateKey.substring(1)}g']) {
        final error = await Ncryptsec.encrypt(
          key,
          'password',
          logN: 3,
        ).then<Object?>((_) => null, onError: (Object e) => e);

        expect('$error', isNot(contains(privateKey.substring(1, 63))));
      }
    });

    test('rejects a log_n outside 1 to maxLogN', () {
      expect(
        Ncryptsec.encrypt(privateKey, 'password', logN: 0),
        throwsA(isA<RangeError>()),
      );
      expect(
        Ncryptsec.encrypt(privateKey, 'password', logN: Ncryptsec.maxLogN + 1),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('decode', () {
    late Ncryptsec ncryptsec;
    late List<int> payload;

    setUpAll(() async {
      ncryptsec = await Ncryptsec.encrypt(privateKey, 'password', logN: 4);
      payload = payloadOf(ncryptsec);
    });

    test('accepts an all uppercase ncryptsec', () {
      expect(Ncryptsec.decode(ncryptsec.encode().toUpperCase()), ncryptsec);
    });

    test('ignores whitespace around the input', () {
      expect(Ncryptsec.decode(' ${ncryptsec.encode()}\n'), ncryptsec);
    });

    test('rejects a log_n of 0', () {
      expect(
        () => decodePayload([...payload]..[1] = 0),
        throwsFormatMessage('Not an ncryptsec: logN is 0'),
      );
    });

    test('rejects an unsupported version', () {
      for (final version in [0x00, 0x01, 0x03]) {
        expect(
          () => decodePayload([...payload]..[0] = version),
          throwsFormatMessage('Unsupported ncryptsec version $version'),
        );
      }
    });

    test('rejects an unknown key security byte', () {
      expect(
        () => decodePayload([...payload]..[42] = 0x03),
        throwsFormatMessage('Not an ncryptsec: key security 3'),
      );
    });

    test('rejects a payload that is not 91 bytes', () {
      for (final bytes in [
        payload.sublist(0, 90),
        [...payload, 0],
        <int>[],
      ]) {
        expect(
          () => decodePayload(bytes),
          throwsFormatMessage('Not an ncryptsec: ${bytes.length} bytes'),
        );
      }
    });

    test('rejects a truncated or malformed string', () {
      final string = ncryptsec.encode();
      final malformed = [
        string.substring(0, string.length - 1),
        string.substring(0, 100),
        string.substring(0, 20),
        '',
        'ncryptsec',
        'ncryptsec1',
        'N${string.substring(1)}',
        '${string.substring(0, 40)}b${string.substring(41)}',
      ];
      for (final input in malformed) {
        expect(
          () => Ncryptsec.decode(input),
          throwsA(isA<FormatException>()),
          reason: input,
        );
        expect(Ncryptsec.tryDecode(input), isNull);
      }
    });

    test('rejects a string with a bad bech32 checksum', () {
      final string = ncryptsec.encode();
      final last = string[string.length - 1];
      final broken =
          '${string.substring(0, string.length - 1)}${last == 'q' ? 'p' : 'q'}';

      expect(
        () => Ncryptsec.decode(broken),
        throwsFormatMessage('Not bech32: invalid checksum'),
      );
    });

    test('rejects another bech32 prefix', () {
      for (final prefix in ['nsec', 'ncrypt', 'ncryptsec2']) {
        expect(
          () => Ncryptsec.decode(encodeBech32(prefix, payload)),
          throwsFormatMessage('Expected ncryptsec, got $prefix'),
        );
      }
    });

    test('never quotes an nsec pasted by mistake', () {
      expect(
        () => Ncryptsec.decode(nsec),
        throwsA(
          isA<FormatException>()
              .having((e) => e.source, 'source', isNull)
              .having((e) => '$e', 'toString', isNot(contains(nsec))),
        ),
      );
    });

    test('compares by value', () {
      final copy = Ncryptsec.decode(ncryptsec.encode());

      expect(copy, ncryptsec);
      expect(copy.hashCode, ncryptsec.hashCode);
      expect(decodePayload([...payload]..[90] ^= 1), isNot(ncryptsec));
    });

    test('leaves the encrypted key out of toString', () {
      expect('$ncryptsec', 'Ncryptsec(logN: 4, keySecurity: unknown)');
    });
  });

  group('decrypt', () {
    late Ncryptsec ncryptsec;
    late List<int> payload;

    setUpAll(() async {
      ncryptsec = await Ncryptsec.encrypt(privateKey, 'password', logN: 4);
      payload = payloadOf(ncryptsec);
    });

    test('accepts a log_n equal to maxLogN', () async {
      expect(await ncryptsec.decrypt('password', maxLogN: 4), privateKey);
    });

    test('rejects a log_n above maxLogN without deriving a key', () {
      for (final logN in [Ncryptsec.maxLogN + 1, 255]) {
        expect(
          decodePayload([...payload]..[1] = logN).decrypt('password'),
          throwsA(
            isA<Nip49CostTooHighException>()
                .having((e) => e.logN, 'logN', logN)
                .having((e) => e.maxLogN, 'maxLogN', Ncryptsec.maxLogN),
          ),
        );
      }
      expect(
        ncryptsec.decrypt('password', maxLogN: 3),
        throwsA(isA<Nip49CostTooHighException>()),
      );
    });

    test('rejects a wrong password', () {
      expect(ncryptsec.decrypt('Password'), throwsWrongPassword);
      expect(ncryptsec.decrypt('password '), throwsWrongPassword);
    });

    test('authenticates the key security byte', () {
      expect(
        decodePayload([...payload]..[42] = 0x01).decrypt('password'),
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
          decodePayload(changed).decrypt('password'),
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

      final fromNormalized = await Ncryptsec.encrypt(
        privateKey,
        normalized,
        logN: 3,
      );
      expect(await fromNormalized.decrypt(input), privateKey);

      final fromInput = await Ncryptsec.encrypt(privateKey, input, logN: 3);
      expect(await fromInput.decrypt(normalized), privateKey);
    });

    test('treats decomposed and composed accents as one password', () async {
      final ncryptsec = await Ncryptsec.encrypt(privateKey, 'café', logN: 3);

      expect(await ncryptsec.decrypt('café'), privateKey);
    });

    test('folds compatibility characters', () async {
      final ncryptsec = await Ncryptsec.encrypt(privateKey, 'ﬁle', logN: 3);

      expect(await ncryptsec.decrypt('file'), privateKey);
    });

    test('keeps distinct characters distinct', () async {
      final ncryptsec = await Ncryptsec.encrypt(privateKey, 'Å', logN: 3);

      expect(ncryptsec.decrypt('A'), throwsWrongPassword);
      expect(ncryptsec.decrypt('å'), throwsWrongPassword);
    });
  });
}
