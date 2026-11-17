import 'dart:math';

/// [bytes] secure random bytes, as a hex string of twice as many characters.
String secureRandomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
