import 'dart:convert';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_zaps/dostr_zaps.dart';
import 'package:test/test.dart';

const server = 'serverPubkey';
const recipient = 'recipientPubkey';
const sender = 'senderPubkey';
const lnurl =
    'lnurl1dp68gurn8ghj7um5v93kketj9ehx2amn9uh8wetvdskkkmn0wahz7mrww4excup0dajx2mrv92x9xp';

/// A request for 1500 sats from [sender] to [recipient], unless told otherwise.
String zapRequest({
  String to = recipient,
  int kind = ZapRequest.kZapRequestKind,
  List<List<String>> tags = const [
    ['amount', '1500000'],
    ['lnurl', lnurl],
  ],
}) => jsonEncode({
  'pubkey': sender,
  'kind': kind,
  'sig': 'sig',
  'created_at': 1234567880,
  'content': 'thanks!',
  'tags': [
    ['p', to],
    ...tags,
  ],
});

/// A receipt signed by [server] for an invoice of 1500 sats, unless told
/// otherwise.
Nip01Event receipt({
  String pubkey = server,
  int kind = ZapReceipt.kKind,
  String bolt11 = 'lnbc15u1p3xnhl2pp5',
  String? description,
  List<List<String>> tags = const [],
}) => Nip01Event(
  pubkey: pubkey,
  kind: kind,
  tags: [
    ['p', recipient],
    ['bolt11', bolt11],
    ['description', description ?? zapRequest()],
    ...tags,
  ],
  content: '',
  createdAt: 1234567890,
);

void main() {
  group('ZapReceipt.fromEvent', () {
    test('reads the receipt and its zap request', () {
      final zapReceipt = ZapReceipt.fromEvent(
        receipt(
          tags: [
            ['preimage', 'preimage'],
            ['e', 'eventId'],
            ['anon', 'anon'],
          ],
        ),
      );

      expect(zapReceipt.pubkey, server);
      expect(zapReceipt.paidAt, 1234567890);
      expect(zapReceipt.bolt11, 'lnbc15u1p3xnhl2pp5');
      expect(zapReceipt.amountMsats, 1500000);
      expect(zapReceipt.amountSats, 1500);
      expect(zapReceipt.preimage, 'preimage');
      expect(zapReceipt.recipient, recipient);
      expect(zapReceipt.eventId, 'eventId');
      expect(zapReceipt.anon, 'anon');
      expect(zapReceipt.zapRequest!.kind, ZapRequest.kZapRequestKind);
      expect(zapReceipt.sender, sender);
      expect(zapReceipt.comment, 'thanks!');
      expect(zapReceipt.lnurl, lnurl);
    });

    test('throws an ArgumentError for another kind', () {
      expect(
        () => ZapReceipt.fromEvent(receipt(kind: 1)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('has no zap request when the description is not one', () {
      for (final description in ['not json', '[]', '{}', zapRequest(kind: 1)]) {
        final zapReceipt = ZapReceipt.fromEvent(
          receipt(description: description),
        );

        expect(zapReceipt.zapRequest, isNull, reason: description);
        expect(zapReceipt.sender, isNull);
      }
    });

    test('ignores tags without a value', () {
      final zapReceipt = ZapReceipt.fromEvent(
        Nip01Event(
          pubkey: server,
          kind: ZapReceipt.kKind,
          tags: [
            ['p'],
            ['bolt11'],
            ['description'],
          ],
          content: '',
        ),
      );

      expect(zapReceipt.recipient, isNull);
      expect(zapReceipt.bolt11, isNull);
      expect(zapReceipt.amountMsats, isNull);
      expect(zapReceipt.zapRequest, isNull);
    });
  });

  group('ZapReceipt.isValid', () {
    bool isValid(Nip01Event event, {String? recipientLnurl = lnurl}) =>
        ZapReceipt.fromEvent(
          event,
        ).isValid(nostrPubkey: server, recipientLnurl: recipientLnurl);

    test('accepts a receipt that matches its zap request', () {
      expect(isValid(receipt()), isTrue);
    });

    test('compares the lnurl ignoring case', () {
      expect(isValid(receipt(), recipientLnurl: lnurl.toUpperCase()), isTrue);
    });

    test('accepts a zap request without amount or lnurl', () {
      expect(isValid(receipt(description: zapRequest(tags: []))), isTrue);
      expect(isValid(receipt(), recipientLnurl: null), isTrue);
    });

    test('refuses a receipt that another key signed', () {
      expect(isValid(receipt(pubkey: 'otherPubkey')), isFalse);
    });

    test('refuses an invoice of another amount', () {
      expect(isValid(receipt(bolt11: 'lnbc20u1p3xnhl2pp5')), isFalse);
    });

    test('refuses an amount that differs by less than a sat', () {
      final description = zapRequest(
        tags: [
          ['amount', '1500400'],
        ],
      );

      expect(isValid(receipt(description: description)), isFalse);
    });

    test('refuses an invoice without amount', () {
      expect(isValid(receipt(bolt11: 'lnbc1p3xnhl2pp5')), isFalse);
    });

    test('refuses the lnurl of someone else', () {
      expect(isValid(receipt(), recipientLnurl: 'lnurl1other'), isFalse);
    });

    test('refuses a receipt without zap request', () {
      expect(isValid(receipt(description: 'not json')), isFalse);
    });

    test('refuses a zap request to someone else', () {
      expect(
        isValid(receipt(description: zapRequest(to: 'otherPubkey'))),
        isFalse,
      );
    });
  });
}
