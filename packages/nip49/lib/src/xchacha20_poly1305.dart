import 'dart:math' show min;
import 'dart:typed_data';

// ChaCha20-Poly1305 (RFC 8439) and XChaCha20-Poly1305
// (draft-irtf-cfrg-xchacha), in integers that stay exact once compiled to
// JavaScript.

const _sigma = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574];
const _tagLength = 16;

/// [plaintext] encrypted under the 32 byte [key] and the 24 byte [nonce],
/// followed by its 16 byte tag, which also covers [aad].
Uint8List xchacha20Poly1305Encrypt(
  Uint8List key,
  Uint8List nonce,
  List<int> plaintext,
  List<int> aad,
) {
  final subkey = hchacha20(key, nonce.sublist(0, 16));
  try {
    return chacha20Poly1305Encrypt(subkey, _ietfNonce(nonce), plaintext, aad);
  } finally {
    subkey.fillRange(0, subkey.length, 0);
  }
}

/// The plaintext of [sealed], a ciphertext followed by its tag, or null when
/// the tag does not match [key], [nonce] and [aad].
Uint8List? xchacha20Poly1305Decrypt(
  Uint8List key,
  Uint8List nonce,
  List<int> sealed,
  List<int> aad,
) {
  final subkey = hchacha20(key, nonce.sublist(0, 16));
  try {
    return chacha20Poly1305Decrypt(subkey, _ietfNonce(nonce), sealed, aad);
  } finally {
    subkey.fillRange(0, subkey.length, 0);
  }
}

Uint8List _ietfNonce(Uint8List nonce) =>
    Uint8List(12)..setRange(4, 12, nonce, 16);

/// [plaintext] encrypted under the 32 byte [key] and the 12 byte [nonce],
/// followed by its 16 byte tag, which also covers [aad].
Uint8List chacha20Poly1305Encrypt(
  Uint8List key,
  Uint8List nonce,
  List<int> plaintext,
  List<int> aad,
) {
  final ciphertext = _chacha20(key, nonce, plaintext, counter: 1);
  return Uint8List(ciphertext.length + _tagLength)
    ..setAll(0, ciphertext)
    ..setAll(ciphertext.length, _tag(key, nonce, ciphertext, aad));
}

/// The plaintext of [sealed], a ciphertext followed by its tag, or null when
/// the tag does not match [key], [nonce] and [aad].
Uint8List? chacha20Poly1305Decrypt(
  Uint8List key,
  Uint8List nonce,
  List<int> sealed,
  List<int> aad,
) {
  if (sealed.length < _tagLength) return null;
  final ciphertext = sealed.sublist(0, sealed.length - _tagLength);
  final tag = _tag(key, nonce, ciphertext, aad);
  var difference = 0;
  for (var i = 0; i < _tagLength; i++) {
    difference |= tag[i] ^ sealed[ciphertext.length + i];
  }
  if (difference != 0) return null;
  return _chacha20(key, nonce, ciphertext, counter: 1);
}

Uint8List _tag(
  Uint8List key,
  Uint8List nonce,
  List<int> ciphertext,
  List<int> aad,
) {
  final oneTimeKey = _chacha20(key, nonce, Uint8List(32), counter: 0);
  final ciphertextStart = _padded(aad.length);
  final lengthsStart = ciphertextStart + _padded(ciphertext.length);
  final message = Uint8List(lengthsStart + 16)
    ..setAll(0, aad)
    ..setAll(ciphertextStart, ciphertext);
  // Two 32-bit halves: ByteData.setUint64 throws on the web.
  ByteData.sublistView(message)
    ..setUint32(lengthsStart, aad.length, Endian.little)
    ..setUint32(lengthsStart + 8, ciphertext.length, Endian.little);
  try {
    return poly1305(oneTimeKey, message);
  } finally {
    oneTimeKey.fillRange(0, oneTimeKey.length, 0);
  }
}

int _padded(int length) => (length + 15) ~/ 16 * 16;

/// The 32 byte subkey HChaCha20 derives from the 32 byte [key] and the 16
/// byte [nonce].
Uint8List hchacha20(Uint8List key, Uint8List nonce) {
  final state = _initialState(key, nonce);
  _rounds(state);
  final subkey = Uint8List(32);
  final data = ByteData.sublistView(subkey);
  for (var i = 0; i < 4; i++) {
    data.setUint32(4 * i, state[i], Endian.little);
    data.setUint32(16 + 4 * i, state[12 + i], Endian.little);
  }
  state.fillRange(0, state.length, 0);
  return subkey;
}

Uint8List _chacha20(
  Uint8List key,
  Uint8List nonce,
  List<int> input, {
  required int counter,
}) {
  final output = Uint8List(input.length);
  final blockInput = Uint8List(16)..setRange(4, 16, nonce);
  final keystream = Uint8List(64);
  final keystreamData = ByteData.sublistView(keystream);
  for (var offset = 0; offset < input.length; offset += 64) {
    ByteData.sublistView(blockInput).setUint32(0, counter++, Endian.little);
    final initial = _initialState(key, blockInput);
    final state = Uint32List.fromList(initial);
    _rounds(state);
    for (var i = 0; i < 16; i++) {
      keystreamData.setUint32(
        4 * i,
        (state[i] + initial[i]) & 0xffffffff,
        Endian.little,
      );
    }
    initial.fillRange(0, initial.length, 0);
    state.fillRange(0, state.length, 0);
    final end = min(offset + 64, input.length);
    for (var i = offset; i < end; i++) {
      output[i] = input[i] ^ keystream[i - offset];
    }
  }
  keystream.fillRange(0, keystream.length, 0);
  return output;
}

Uint32List _initialState(Uint8List key, Uint8List input) {
  final keyData = ByteData.sublistView(key);
  final inputData = ByteData.sublistView(input);
  final state = Uint32List(16)..setAll(0, _sigma);
  for (var i = 0; i < 8; i++) {
    state[4 + i] = keyData.getUint32(4 * i, Endian.little);
  }
  for (var i = 0; i < 4; i++) {
    state[12 + i] = inputData.getUint32(4 * i, Endian.little);
  }
  return state;
}

void _rounds(Uint32List x) {
  for (var i = 0; i < 10; i++) {
    _quarterRound(x, 0, 4, 8, 12);
    _quarterRound(x, 1, 5, 9, 13);
    _quarterRound(x, 2, 6, 10, 14);
    _quarterRound(x, 3, 7, 11, 15);
    _quarterRound(x, 0, 5, 10, 15);
    _quarterRound(x, 1, 6, 11, 12);
    _quarterRound(x, 2, 7, 8, 13);
    _quarterRound(x, 3, 4, 9, 14);
  }
}

void _quarterRound(Uint32List x, int a, int b, int c, int d) {
  x[a] += x[b];
  x[d] = _rotl(x[d] ^ x[a], 16);
  x[c] += x[d];
  x[b] = _rotl(x[b] ^ x[c], 12);
  x[a] += x[b];
  x[d] = _rotl(x[d] ^ x[a], 8);
  x[c] += x[d];
  x[b] = _rotl(x[b] ^ x[c], 7);
}

int _rotl(int a, int bits) => ((a << bits) | (a >>> (32 - bits))) & 0xffffffff;

/// The Poly1305 tag of [message] under the 32 byte one-time [key].
///
/// Works on ten limbs of 13 bits, so that a product of limbs and its sums stay
/// below 2^53, where JavaScript numbers are still exact.
Uint8List poly1305(Uint8List key, List<int> message) {
  final rBytes = Uint8List(17)..setRange(0, 16, key);
  for (final i in [3, 7, 11, 15]) {
    rBytes[i] &= 0x0f;
  }
  for (final i in [4, 8, 12]) {
    rBytes[i] &= 0xfc;
  }
  final r = _limbs(rBytes);
  final h = List<int>.filled(10, 0);
  final block = Uint8List(17);
  for (var offset = 0; offset < message.length; offset += 16) {
    final length = min(16, message.length - offset);
    block
      ..fillRange(0, block.length, 0)
      ..setRange(0, length, message, offset);
    block[length] = 1;
    final m = _limbs(block);
    for (var i = 0; i < 10; i++) {
      h[i] += m[i];
    }
    _multiply(h, r);
  }

  _carry(h);
  _carry(h);
  final g = List<int>.filled(10, 0);
  var carry = 5;
  for (var i = 0; i < 10; i++) {
    final value = h[i] + carry;
    carry = value >> 13;
    g[i] = value & 0x1fff;
  }
  // carry is 1 when h is at least 2^130 - 5, and g is then h - (2^130 - 5).
  final mask = -carry;
  for (var i = 0; i < 10; i++) {
    h[i] = (g[i] & mask) | (h[i] & ~mask);
  }

  final tag = Uint8List(16);
  var accumulator = 0;
  var bits = 0;
  var next = 0;
  for (final limb in h) {
    accumulator |= limb << bits;
    bits += 13;
    while (bits >= 8 && next < 16) {
      tag[next++] = accumulator & 0xff;
      accumulator >>= 8;
      bits -= 8;
    }
  }
  carry = 0;
  for (var i = 0; i < 16; i++) {
    final value = tag[i] + key[16 + i] + carry;
    tag[i] = value & 0xff;
    carry = value >> 8;
  }

  rBytes.fillRange(0, rBytes.length, 0);
  for (final limbs in [r, h, g]) {
    limbs.fillRange(0, limbs.length, 0);
  }
  return tag;
}

/// The 130 low bits of [bytes], 17 bytes in little endian, as limbs of 13 bits.
List<int> _limbs(Uint8List bytes) {
  final limbs = List<int>.filled(10, 0);
  var accumulator = 0;
  var bits = 0;
  var next = 0;
  for (var i = 0; i < 10; i++) {
    while (bits < 13) {
      accumulator |= bytes[next++] << bits;
      bits += 8;
    }
    limbs[i] = accumulator & 0x1fff;
    accumulator >>= 13;
    bits -= 13;
  }
  return limbs;
}

/// [h] times [r] modulo 2^130 - 5, where 2^130 is worth 5. The sums reach
/// 2^34, past the 32 bits of the bitwise operators on the web, so the carries
/// divide instead of shifting.
void _multiply(List<int> h, List<int> r) {
  final d = List<int>.filled(10, 0);
  for (var i = 0; i < 10; i++) {
    for (var j = 0; j < 10; j++) {
      d[i] += h[j] * (j <= i ? r[i - j] : 5 * r[i + 10 - j]);
    }
  }
  var carry = 0;
  for (var i = 0; i < 10; i++) {
    final value = d[i] + carry;
    carry = value ~/ 0x2000;
    h[i] = value - carry * 0x2000;
  }
  h[0] += carry * 5;
  carry = h[0] ~/ 0x2000;
  h[0] -= carry * 0x2000;
  h[1] += carry;
  d.fillRange(0, d.length, 0);
}

void _carry(List<int> h) {
  var carry = 0;
  for (var i = 0; i < 10; i++) {
    final value = h[i] + carry;
    carry = value >> 13;
    h[i] = value & 0x1fff;
  }
  h[0] += carry * 5;
}
