import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/stream/chacha7539.dart';

typedef MessageKeys = ({
  Uint8List chachaKey,
  Uint8List chachaNonce,
  Uint8List hmacKey,
});

typedef Payload = ({Uint8List nonce, Uint8List ciphertext, Uint8List mac});

const _version = 2;

Uint8List secureRandomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

MessageKeys deriveMessageKeys(Uint8List conversationKey, Uint8List nonce) {
  if (conversationKey.length != 32) {
    throw ArgumentError('must be 32 bytes', 'conversationKey');
  }
  if (nonce.length != 32) {
    throw ArgumentError('must be 32 bytes', 'nonce');
  }
  final keys = hkdfExpand(prk: conversationKey, info: nonce, length: 76);
  return (
    chachaKey: keys.sublist(0, 32),
    chachaNonce: keys.sublist(32, 44),
    hmacKey: keys.sublist(44, 76),
  );
}

Uint8List pad(Uint8List plaintext) {
  final length = plaintext.length;
  if (length < 1 || length > 65535) {
    throw ArgumentError(
      'must be 1 to 65535 bytes in UTF-8, not $length',
      'plaintext',
    );
  }
  return Uint8List(2 + calcPaddedLen(length))
    ..[0] = length >> 8
    ..[1] = length
    ..setRange(2, 2 + length, plaintext);
}

int calcPaddedLen(int unpaddedLen) {
  if (unpaddedLen <= 32) {
    return 32;
  }
  final nextPower = 1 << (unpaddedLen - 1).bitLength;
  final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
  return chunk * ((unpaddedLen - 1) ~/ chunk + 1);
}

Uint8List unpad(Uint8List padded) {
  final length = padded[0] << 8 | padded[1];
  if (length == 0 || padded.length != 2 + calcPaddedLen(length)) {
    throw const FormatException('Invalid padding');
  }
  return padded.sublist(2, 2 + length);
}

Uint8List chaCha20(Uint8List key, Uint8List nonce, Uint8List input) {
  final engine = ChaCha7539Engine()
    ..init(true, ParametersWithIV(KeyParameter(key), nonce));
  return engine.process(input);
}

Uint8List _hmacSha256(Uint8List key, List<int> data) {
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
  return hmac.process(Uint8List.fromList(data));
}

Uint8List hkdfExtract({required Uint8List ikm, required Uint8List salt}) {
  return _hmacSha256(salt, ikm);
}

Uint8List hkdfExpand({
  required Uint8List prk,
  required Uint8List info,
  required int length,
}) {
  const hashLength = 32;
  final blocks = (length + hashLength - 1) ~/ hashLength;
  final okm = <int>[];
  var previous = <int>[];
  for (var i = 1; i <= blocks; i++) {
    previous = _hmacSha256(prk, [...previous, ...info, i]);
    okm.addAll(previous);
  }
  return Uint8List.fromList(okm.sublist(0, length));
}

Uint8List calculateMac(Uint8List key, Uint8List nonce, Uint8List ciphertext) {
  return _hmacSha256(key, [...nonce, ...ciphertext]);
}

bool macMatches(
  Uint8List hmacKey,
  Uint8List nonce,
  Uint8List ciphertext,
  Uint8List mac,
) {
  final expected = calculateMac(hmacKey, nonce, ciphertext);
  if (expected.length != mac.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < mac.length; i++) {
    diff |= expected[i] ^ mac[i];
  }
  return diff == 0;
}

String constructPayload(Uint8List nonce, Uint8List ciphertext, Uint8List mac) {
  return base64.encode([_version, ...nonce, ...ciphertext, ...mac]);
}

Payload parsePayload(String payload) {
  if (payload.startsWith('#')) {
    throw const FormatException('Unknown version');
  }
  if (payload.length < 132 || payload.length > 87472) {
    throw const FormatException('Invalid payload size');
  }
  final data = base64.decode(payload);
  if (data.length < 99 || data.length > 65603) {
    throw const FormatException('Invalid data size');
  }
  if (data[0] != _version) {
    throw const FormatException('Unknown version');
  }
  return (
    nonce: data.sublist(1, 33),
    ciphertext: data.sublist(33, data.length - 32),
    mac: data.sublist(data.length - 32),
  );
}
