import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithIV;
import 'package:pointycastle/stream/chacha7539.dart';

typedef MessageKeys = ({
  Uint8List chachaKey,
  Uint8List chachaNonce,
  Uint8List hmacKey,
});

typedef Payload = ({Uint8List nonce, Uint8List ciphertext, Uint8List mac});

const _version = 2;
const _maxPlaintextLength = 0xffffffff;
const _extendedPrefixThreshold = 0x10000;

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
  if (length < 1 || length > _maxPlaintextLength) {
    throw ArgumentError(
      'must be 1 to $_maxPlaintextLength bytes in UTF-8, not $length',
      'plaintext',
    );
  }
  final extended = length >= _extendedPrefixThreshold;
  final prefixLength = extended ? 6 : 2;
  final padded = Uint8List(prefixLength + calcPaddedLen(length));
  final view = ByteData.sublistView(padded);
  if (extended) {
    view.setUint32(2, length);
  } else {
    view.setUint16(0, length);
  }
  return padded..setRange(prefixLength, prefixLength + length, plaintext);
}

int calcPaddedLen(int unpaddedLen) {
  if (unpaddedLen <= 32) {
    return 32;
  }
  // No bit shift: shifts are 32-bit on the web, and this reaches 2^32.
  var nextPower = 32;
  while (nextPower < unpaddedLen) {
    nextPower *= 2;
  }
  final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
  return chunk * ((unpaddedLen - 1) ~/ chunk + 1);
}

Uint8List unpad(Uint8List padded) {
  final view = ByteData.sublistView(padded);
  final extended = view.getUint16(0) == 0;
  final prefixLength = extended ? 6 : 2;
  final length = extended ? view.getUint32(2) : view.getUint16(0);
  if ((extended && length < _extendedPrefixThreshold) ||
      padded.length != prefixLength + calcPaddedLen(length)) {
    throw const FormatException('Invalid padding');
  }
  return Uint8List.sublistView(padded, prefixLength, prefixLength + length);
}

Uint8List chaCha20(Uint8List key, Uint8List nonce, Uint8List input) {
  final engine = ChaCha7539Engine()
    ..init(true, ParametersWithIV(KeyParameter(key), nonce));
  return engine.process(input);
}

Uint8List _hmacSha256(Uint8List key, List<Uint8List> parts) {
  final output = AccumulatorSink<Digest>();
  final input = Hmac(sha256, key).startChunkedConversion(output);
  parts.forEach(input.add);
  input.close();
  return Uint8List.fromList(output.events.single.bytes);
}

Uint8List hkdfExtract({required Uint8List ikm, required Uint8List salt}) {
  return _hmacSha256(salt, [ikm]);
}

Uint8List hkdfExpand({
  required Uint8List prk,
  required Uint8List info,
  required int length,
}) {
  const hashLength = 32;
  final blocks = (length + hashLength - 1) ~/ hashLength;
  final okm = <int>[];
  var previous = Uint8List(0);
  for (var i = 1; i <= blocks; i++) {
    previous = _hmacSha256(prk, [
      previous,
      info,
      Uint8List.fromList([i]),
    ]);
    okm.addAll(previous);
  }
  return Uint8List.fromList(okm.sublist(0, length));
}

Uint8List calculateMac(Uint8List key, Uint8List nonce, Uint8List ciphertext) {
  return _hmacSha256(key, [nonce, ciphertext]);
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
  final bytes = BytesBuilder(copy: false)
    ..addByte(_version)
    ..add(nonce)
    ..add(ciphertext)
    ..add(mac);
  return base64.encode(bytes.takeBytes());
}

Payload parsePayload(String payload) {
  if (payload.startsWith('#')) {
    throw const FormatException('Unknown version');
  }
  if (payload.length < 132) {
    throw const FormatException('Invalid payload size');
  }
  final data = base64.decode(payload);
  if (data.length < 99) {
    throw const FormatException('Invalid data size');
  }
  if (data[0] != _version) {
    throw const FormatException('Unknown version');
  }
  return (
    nonce: Uint8List.sublistView(data, 1, 33),
    ciphertext: Uint8List.sublistView(data, 33, data.length - 32),
    mac: Uint8List.sublistView(data, data.length - 32),
  );
}
