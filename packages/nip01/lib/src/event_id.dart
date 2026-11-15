import 'dart:convert';

import 'package:crypto/crypto.dart';

String computeEventId({
  required String pubkey,
  required int createdAt,
  required int kind,
  required List<List<String>> tags,
  required String content,
}) {
  final serialized = json.encode([0, pubkey, createdAt, kind, tags, content]);
  return sha256.convert(utf8.encode(serialized)).toString();
}
