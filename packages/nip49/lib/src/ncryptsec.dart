import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'bech32.dart';
import 'hex.dart';
import 'nip49_exception.dart';
import 'run_off_main_thread_web.dart'
    if (dart.library.io) 'run_off_main_thread.dart';
import 'scrypt.dart';
import 'xchacha20_poly1305.dart';

/// How the private key was handled before being encrypted.
enum Nip49KeySecurity {
  /// Known to have been handled insecurely (stored or pasted unencrypted).
  insecure(0x00),

  /// Not known to have been handled insecurely.
  secure(0x01),

  /// The client does not track it.
  unknown(0x02);

  final int value;

  const Nip49KeySecurity(this.value);
}

/// An `ncryptsec`: a private key encrypted with a password, as
/// [NIP-49](https://github.com/nostr-protocol/nips/blob/master/49.md)
/// defines it.
///
/// On web, scrypt runs on the main thread and blocks the UI while it runs.
final class Ncryptsec {
  /// The prefix of an ncryptsec.
  static const prefix = 'ncryptsec';

  /// The scrypt cost [encrypt] uses by default.
  static const defaultLogN = 16;

  /// 1 GiB of scrypt memory, the same cap as nostr-tools.
  static const maxLogN = 20;

  static const _version = 0x02;
  static const _length = 91;

  final Uint8List _payload;

  const Ncryptsec._(this._payload);

  /// Decodes [input], ignoring whitespace around it. Throws a
  /// [FormatException] when it is not an ncryptsec, whose message never
  /// quotes the input.
  factory Ncryptsec.decode(String input) {
    final (decodedPrefix, payload) = decodeBech32(input.trim());
    if (decodedPrefix != prefix) {
      throw FormatException('Expected $prefix, got $decodedPrefix');
    }
    if (payload.length != _length) {
      throw FormatException('Not an $prefix: ${payload.length} bytes');
    }
    if (payload[0] != _version) {
      throw FormatException('Unsupported $prefix version ${payload[0]}');
    }
    if (payload[1] == 0) {
      throw FormatException('Not an $prefix: logN is 0');
    }
    if (!Nip49KeySecurity.values.any((s) => s.value == payload[42])) {
      throw FormatException('Not an $prefix: key security ${payload[42]}');
    }
    return Ncryptsec._(Uint8List.fromList(payload));
  }

  /// [input] decoded like [Ncryptsec.decode], or null when it is not an
  /// ncryptsec.
  static Ncryptsec? tryDecode(String input) {
    try {
      return Ncryptsec.decode(input);
    } on FormatException {
      return null;
    }
  }

  /// Encrypts the hex [privateKey], in lowercase or uppercase, with
  /// [password].
  ///
  /// Throws an [ArgumentError] when [privateKey] is not 32 bytes of hex, and a
  /// [RangeError] for a [logN] outside 1 to [maxLogN].
  static Future<Ncryptsec> encrypt(
    String privateKey,
    String password, {
    int logN = defaultLogN,
    Nip49KeySecurity keySecurity = Nip49KeySecurity.unknown,
  }) async {
    RangeError.checkValueInInterval(logN, 1, maxLogN, 'logN');
    final privateKeyBytes = privateKey.length == 64
        ? tryHexToBytes(privateKey)
        : null;
    // No message quotes the key.
    if (privateKeyBytes == null) {
      throw ArgumentError('must be 32 bytes of hex', 'privateKey');
    }

    final salt = _randomBytes(16);
    final nonce = _randomBytes(24);
    final symmetricKey = await _deriveKey(password, salt, logN);
    final Uint8List sealed;
    try {
      sealed = xchacha20Poly1305Encrypt(symmetricKey, nonce, privateKeyBytes, [
        keySecurity.value,
      ]);
    } finally {
      symmetricKey.fillRange(0, symmetricKey.length, 0);
      privateKeyBytes.fillRange(0, privateKeyBytes.length, 0);
    }

    return Ncryptsec._(
      Uint8List.fromList([
        _version,
        logN,
        ...salt,
        ...nonce,
        keySecurity.value,
        ...sealed,
      ]),
    );
  }

  /// The scrypt cost: [decrypt] takes 2^logN KiB of memory, 64 MiB at 16, and
  /// each step up doubles its time and memory.
  ///
  /// Readable without the password, like [keySecurity], but only checked by
  /// [decrypt], which fails with [Nip49WrongPasswordException] when either
  /// was altered.
  int get logN => _payload[1];

  /// How the private key was handled before it was encrypted.
  Nip49KeySecurity get keySecurity =>
      Nip49KeySecurity.values.firstWhere((s) => s.value == _payload[42]);

  /// Decrypts the private key with [password], and returns it as lowercase
  /// hex.
  ///
  /// Throws [Nip49CostTooHighException] before any scrypt work when [logN] is
  /// above [maxLogN]. Lower it on devices with little memory: logN 20
  /// allocates 1 GiB. Throws [Nip49WrongPasswordException] when the password
  /// is wrong, or when the ncryptsec was altered after it was made.
  Future<String> decrypt(
    String password, {
    int maxLogN = Ncryptsec.maxLogN,
  }) async {
    if (logN > maxLogN) throw Nip49CostTooHighException(logN, maxLogN);

    final symmetricKey = await _deriveKey(
      password,
      _payload.sublist(2, 18),
      logN,
    );
    final privateKey = xchacha20Poly1305Decrypt(
      symmetricKey,
      _payload.sublist(18, 42),
      _payload.sublist(43),
      [_payload[42]],
    );
    symmetricKey.fillRange(0, symmetricKey.length, 0);
    if (privateKey == null) throw const Nip49WrongPasswordException();

    final privateKeyHex = bytesToHex(privateKey);
    privateKey.fillRange(0, privateKey.length, 0);
    return privateKeyHex;
  }

  /// This ncryptsec as a bech32 string.
  String encode() => encodeBech32(prefix, _payload);

  @override
  bool operator ==(Object other) {
    if (other is! Ncryptsec) return false;
    for (var i = 0; i < _length; i++) {
      if (other._payload[i] != _payload[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_payload);

  /// Leaves the encrypted key out, which a log would expose to offline
  /// password guessing.
  @override
  String toString() =>
      'Ncryptsec(logN: $logN, keySecurity: ${keySecurity.name})';
}

Future<Uint8List> _deriveKey(String password, Uint8List salt, int logN) =>
    runOffMainThread(_scrypt, (password: password, salt: salt, logN: logN));

Uint8List _scrypt(({String password, Uint8List salt, int logN}) params) {
  final password = utf8.encode(unorm.nfkc(params.password));
  try {
    return scrypt(
      password,
      params.salt,
      n: 1 << params.logN,
      r: 8,
      p: 1,
      dkLen: 32,
    );
  } finally {
    password.fillRange(0, password.length, 0);
  }
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}
