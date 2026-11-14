import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';

/// A color hashed from [pubkey], at a fixed saturation and lightness so that
/// every pubkey stays readable.
Color colorFromPubkey(String pubkey) {
  final hash = sha256.convert(utf8.encode(pubkey)).bytes;
  return HSLColor.fromColor(
    Color.fromARGB(255, hash[0], hash[1], hash[2]),
  ).withSaturation(0.6).withLightness(0.45).toColor();
}
