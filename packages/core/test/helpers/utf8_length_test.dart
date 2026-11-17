import 'dart:convert';

import 'package:dostr_core/src/helpers/utf8_length.dart';
import 'package:test/test.dart';

void main() {
  test('counts the bytes utf8.encode writes', () {
    const strings = [
      '',
      'abc',
      'é',
      '€',
      '😀',
      '["EVENT","sub",{"content":"gm ☕ 🌅, ça va ?"}]',
      '\uD800',
      '\uDC00',
      'a\uD83D',
      '\uDE00\uD83D',
      '\uD83D😀',
    ];
    for (final string in strings) {
      expect(utf8Length(string), utf8.encode(string).length, reason: string);
    }
  });
}
