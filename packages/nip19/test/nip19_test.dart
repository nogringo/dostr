import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_nip19/src/bech32_codec.dart';
import 'package:dostr_nip19/src/tlv.dart';
import 'package:test/test.dart';

const pubkey =
    '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';
const npub = 'npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg';
const privateKey =
    '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
const nsec = 'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';
const nprofile =
    'nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p';
const eventId =
    'a12ff3d33a94fa408d71e2435e6382700647f0cd3c0c09d56ec2cc64d5164b43';
const author =
    '76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa';
const nevent =
    'nevent1qqs2ztln6vaff7jq34c7ys67vwp8qpj87rxncrqf64hv9nry65tykscprpmhxue69uhhyetvv9ujuetcv9khqmr99ehhyee0qgs8d3c64cayj8canmky0jap0c3fekjpzwsthdhx4cthd4my8c5u47srqsqqqqqpk00gdp';
const naddr =
    'naddr1qqxnzd3cx5urqv3nxymngdphqgsyvrp9u6p0mfur9dfdru3d853tx9mdjuhkphxuxgfwmryja7zsvhqrqsqqql8kavfpw3';

List<int> kindBytes(int kind) => [0, 0, kind >> 8, kind & 0xff];

void main() {
  group('NIP-19 vectors', () {
    test('npub', () {
      expect(Npub.decode(npub).pubkey, pubkey);
      expect(Npub(pubkey).encode(), npub);
    });

    test('nsec', () {
      expect(Nsec.decode(nsec).privateKey, privateKey);
      expect(Nsec(privateKey).encode(), nsec);
    });

    test('nprofile', () {
      final decoded = Nprofile.decode(nprofile);

      expect(
        decoded.pubkey,
        '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
      );
      expect(decoded.relays, ['wss://r.x.com', 'wss://djbas.sadkb.com']);
      expect(decoded.encode(), nprofile);
    });

    test('nevent', () {
      final decoded = Nevent.decode(nevent);

      expect(decoded.eventId, eventId);
      expect(decoded.relays, ['wss://relay.example.org/']);
      expect(decoded.author, author);
      expect(decoded.kind, 1);
      expect(decoded.encode(), nevent);
    });

    test('naddr', () {
      final decoded = Naddr.decode(naddr);

      expect(decoded.identifier, '1685802317447');
      expect(
        decoded.pubkey,
        '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c',
      );
      expect(decoded.kind, 31990);
      expect(decoded.relays, isEmpty);
      expect(decoded.encode(), naddr);
    });
  });

  group('Nip19Entity.decode', () {
    test('returns the entity of each prefix', () {
      String prefixOf(Nip19Entity entity) => switch (entity) {
        Npub() => Npub.prefix,
        Nsec() => Nsec.prefix,
        Note() => Note.prefix,
        Nprofile() => Nprofile.prefix,
        Nevent() => Nevent.prefix,
        Naddr() => Naddr.prefix,
      };

      for (final input in [
        npub,
        nsec,
        Note(eventId).encode(),
        nprofile,
        nevent,
        naddr,
      ]) {
        expect(input, startsWith('${prefixOf(Nip19Entity.decode(input))}1'));
      }
    });

    test('accepts the nostr: prefix of NIP-21', () {
      expect(Nip19Entity.decode('nostr:$npub'), Npub(pubkey));
      expect(Nevent.decode('NOSTR:$nevent').eventId, eventId);
    });

    test('rejects an nsec behind the nostr: prefix', () {
      expect(() => Nsec.decode('nostr:$nsec'), throwsFormatException);
    });

    test('accepts an uppercase string', () {
      expect(Npub.decode(npub.toUpperCase()).pubkey, pubkey);
    });

    final invalid = [
      ('an empty string', ''),
      ('a bare prefix', 'npub'),
      ('a prefix and a separator', 'npub1'),
      ('a string that is not bech32', 'not_bech32'),
      ('characters outside the bech32 set', 'npub1invalid'),
      ('a truncated npub', npub.substring(0, 30)),
      ('a wrong checksum', '${npub.substring(0, npub.length - 1)}q'),
      ('mixed case', 'N${npub.substring(1)}'),
      ('an npub of 31 bytes', encodeBech32('npub', List.filled(31, 1))),
      (
        'an unsupported prefix',
        encodeBech32('nrelay', tlvEntry(0, utf8.encode('wss://r.x.com'))),
      ),
      ('a truncated TLV entry', encodeBech32('nprofile', [0, 32, 1, 2])),
      (
        'an nprofile without a pubkey',
        encodeBech32('nprofile', tlvEntry(1, utf8.encode('wss://r.x.com'))),
      ),
      (
        'an nevent without an event id',
        encodeBech32('nevent', tlvEntry(2, hex.decode(author))),
      ),
      (
        'an naddr without an identifier',
        encodeBech32('naddr', [
          ...tlvEntry(2, hex.decode(pubkey)),
          ...tlvEntry(3, kindBytes(30023)),
        ]),
      ),
      (
        'an naddr without an author',
        encodeBech32('naddr', [
          ...tlvEntry(0, utf8.encode('test')),
          ...tlvEntry(3, kindBytes(30023)),
        ]),
      ),
      (
        'an naddr without a kind',
        encodeBech32('naddr', [
          ...tlvEntry(0, utf8.encode('test')),
          ...tlvEntry(2, hex.decode(pubkey)),
        ]),
      ),
    ];
    for (final (name, input) in invalid) {
      test('throws a FormatException for $name', () {
        expect(() => Nip19Entity.decode(input), throwsFormatException);
        expect(Nip19Entity.tryDecode(input), isNull);
      });
    }

    test('does not quote an nsec in its error', () {
      expect(
        () => Nip19Entity.decode('N${nsec.substring(1)}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains(nsec.substring(5))),
          ),
        ),
      );
    });

    test('does not quote a hex private key in its error', () {
      expect(
        () => Nsec.decode(' $privateKey'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains(privateKey.substring(0, 8))),
          ),
        ),
      );
    });
  });

  group('typed decoding', () {
    test('rejects another entity', () {
      expect(() => Npub.decode(nsec), throwsFormatException);
      expect(Npub.tryDecode(nsec), isNull);
      expect(Nsec.tryDecode(npub), isNull);
      expect(Note.tryDecode(nevent), isNull);
      expect(Nprofile.tryDecode(npub), isNull);
      expect(Nevent.tryDecode(naddr), isNull);
      expect(Naddr.tryDecode(nprofile), isNull);
    });

    test('ignores unknown TLV entries and relays that are not UTF-8', () {
      final input = encodeBech32('nprofile', [
        ...tlvEntry(0, hex.decode(pubkey)),
        ...tlvEntry(1, [0xff, 0xfe]),
        ...tlvEntry(1, utf8.encode('wss://r.x.com')),
        ...tlvEntry(9, [1, 2, 3]),
      ]);

      expect(
        Nprofile.decode(input),
        Nprofile(pubkey: pubkey, relays: ['wss://r.x.com']),
      );
    });

    test('ignores an author or a kind of the wrong length', () {
      final input = encodeBech32('nevent', [
        ...tlvEntry(0, hex.decode(eventId)),
        ...tlvEntry(2, [1, 2, 3]),
        ...tlvEntry(3, [1]),
      ]);

      final decoded = Nevent.decode(input);
      expect(decoded.author, isNull);
      expect(decoded.kind, isNull);
    });
  });

  group('constructors', () {
    test('reject a key that is not 32 bytes of hex', () {
      for (final key in ['', 'abcd', 'ab' * 31, 'zz' * 32, 'ab' * 33]) {
        expect(() => Npub(key), throwsArgumentError, reason: key);
      }
      expect(
        () => Nevent(eventId: eventId, author: 'abcd'),
        throwsArgumentError,
      );
    });

    test('lowercase the hex', () {
      expect(Npub(pubkey.toUpperCase()), Npub(pubkey));
      expect(Npub(pubkey.toUpperCase()).encode(), npub);
    });

    test('reject a relay url longer than 255 bytes', () {
      final relay = 'wss://${'é' * 125}';

      expect(
        () => Nprofile(pubkey: pubkey, relays: [relay]),
        throwsArgumentError,
      );
      expect(
        () => Nevent(eventId: eventId, relays: [relay]),
        throwsArgumentError,
      );
      expect(
        () => Naddr(identifier: '', pubkey: pubkey, kind: 0, relays: [relay]),
        throwsArgumentError,
      );
    });

    test('accept a relay url of 255 bytes', () {
      final relay = 'wss://${'a' * 249}';
      final profile = Nprofile(pubkey: pubkey, relays: [relay]);

      expect(Nprofile.decode(profile.encode()).relays, [relay]);
    });

    test('reject an identifier longer than 255 bytes', () {
      expect(
        () => Naddr(identifier: 'a' * 256, pubkey: pubkey, kind: 30023),
        throwsArgumentError,
      );
    });

    test('reject a kind that does not fit 32 bits', () {
      for (final kind in [-1, 0x100000000]) {
        expect(
          () => Naddr(identifier: '', pubkey: pubkey, kind: kind),
          throwsRangeError,
        );
        expect(() => Nevent(eventId: eventId, kind: kind), throwsRangeError);
      }
    });

    test('copy the relays and keep them from changing', () {
      final relays = ['wss://r.x.com'];
      final profile = Nprofile(pubkey: pubkey, relays: relays);
      relays.add('wss://relay.example.com');

      expect(profile.relays, ['wss://r.x.com']);
      expect(() => profile.relays.add('x'), throwsUnsupportedError);
    });

    test('keep the private key out of the errors and toString of Nsec', () {
      final shortKey = privateKey.substring(2);

      expect(Nsec(privateKey).toString(), isNot(contains(privateKey)));
      expect(
        () => Nsec(shortKey),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains(shortKey)),
          ),
        ),
      );
    });
  });

  group('round trips', () {
    final entities = <Nip19Entity>[
      Npub(pubkey),
      Nsec(privateKey),
      Note(eventId),
      Nprofile(pubkey: pubkey),
      Nprofile(pubkey: pubkey, relays: ['wss://r.x.com', 'wss://a.b.com']),
      Nevent(eventId: eventId),
      Nevent(
        eventId: eventId,
        relays: ['wss://r.x.com'],
        author: author,
        kind: 0xffffffff,
      ),
      Naddr(identifier: '', pubkey: pubkey, kind: 0),
      Naddr(
        identifier: 'café',
        pubkey: pubkey,
        kind: 30023,
        relays: ['wss://r.x.com'],
      ),
    ];
    for (final entity in entities) {
      test('$entity', () {
        final decoded = Nip19Entity.decode(entity.encode());

        expect(decoded, entity);
        expect(decoded.hashCode, entity.hashCode);
      });
    }
  });
}
