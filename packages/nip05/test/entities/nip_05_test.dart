import 'dart:convert';

import 'package:dostr_nip05/dostr_nip05.dart';
import 'package:test/test.dart';

const pubkey =
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';

void main() {
  group('Nip05.canonicalIdentifier', () {
    test('lowercases and trims', () {
      expect(Nip05.canonicalIdentifier(' Bob@Example.COM '), 'bob@example.com');
    });

    test('a bare domain becomes _@domain', () {
      expect(Nip05.canonicalIdentifier('example.com'), '_@example.com');
    });

    test('accepts the characters NIP-05 allows in a name', () {
      expect(
        Nip05.canonicalIdentifier('a.b-c_d9@sub.example-1.com'),
        'a.b-c_d9@sub.example-1.com',
      );
    });

    test('rejects malformed identifiers', () {
      for (final identifier in [
        '',
        '@example.com',
        'bob@',
        'a@b@example.com',
        'bob+tag@example.com',
        'a&name=_@example.com',
        'bob@evil.com/x',
        'bob@evil.com?a=1',
        'bob@evil.com:8080',
        'bob@[::1]',
        'bob@exa mple.com',
        'bob@exämple.com',
        'bob@-example.com',
        'bob@example..com',
      ]) {
        expect(
          Nip05.canonicalIdentifier(identifier),
          isNull,
          reason: identifier,
        );
      }
    });
  });

  group('Nip05Record', () {
    test('reads back equal from JSON', () {
      for (final record in [
        Nip05Record(
          identifier: 'bob@example.com',
          nip05: Nip05(
            identifier: 'bob@example.com',
            pubkey: pubkey,
            relays: [RelayUrl.parse('wss://relay.example.com')],
          ),
          fetchedAt: DateTime.now(),
        ),
        Nip05Record(identifier: 'ghost@example.com', fetchedAt: DateTime.now()),
      ]) {
        final json = jsonDecode(jsonEncode(record.toJson())) as Map;
        expect(Nip05Record.fromJson(json), record);
      }
    });
  });
}
