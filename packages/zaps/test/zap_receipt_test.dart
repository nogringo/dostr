import 'dart:convert';

import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_zaps/ndk_zaps.dart';
import 'package:test/test.dart';

Nip01Event receipt({
  String pubKey = 'testPubKey',
  int kind = 9735,
  List<List<String>> tags = const [],
}) => Nip01Event(
  pubKey: pubKey,
  kind: kind,
  tags: tags,
  content: '',
  createdAt: 1234567890,
);

void main() {
  group('ZapReceipt', () {
    test('fromEvent initializes correctly with valid event', () {
      final zapReceipt = ZapReceipt.fromEvent(
        receipt(
          tags: [
            ['bolt11', 'testBolt11'],
            ['preimage', 'testPreimage'],
            [
              'description',
              jsonEncode({
                'pubkey': 'testSender',
                'kind': ZapRequest.kZapRequestKind,
                'sig': "sig",
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'content': 'testComment',
                'pubKey': 'testSender',
                'tags': [
                  ['lnurl', 'testLnurl'],
                  ['amount', '1000'],
                ],
              }),
            ],
            ['p', 'testRecipient'],
            ['e', 'testEventId'],
            ['anon', 'testAnon'],
            ['P', 'testSender'],
          ],
        ),
      );

      expect(zapReceipt.pubKey, 'testPubKey');
      expect(zapReceipt.bolt11, 'testBolt11');
      expect(zapReceipt.preimage, 'testPreimage');
      expect(zapReceipt.comment, 'testComment');
      expect(zapReceipt.sender, 'testSender');
      expect(zapReceipt.lnurl, 'testLnurl');
      expect(zapReceipt.amountSats, 1); // 1000 msats = 1 sat
      expect(zapReceipt.recipient, 'testRecipient');
      expect(zapReceipt.eventId, 'testEventId');
      expect(zapReceipt.anon, 'testAnon');
      expect(zapReceipt.paidAt, 1234567890);
    });

    test('fromEvent throws exception for non-nip57 event', () {
      expect(() => ZapReceipt.fromEvent(receipt(kind: 1234)), throwsException);
    });

    test('isValid returns true for valid zap receipt', () {
      final zapReceipt = ZapReceipt.fromEvent(
        receipt(
          tags: [
            ['bolt11', 'lnbc15u1p'],
            [
              'description',
              jsonEncode({
                'pubkey': 'testSender',
                'kind': ZapRequest.kZapRequestKind,
                'sig': "sig",
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'content': '',
                'tags': [
                  ['lnurl', 'testLnurl'],
                ],
              }),
            ],
          ],
        ),
      );

      expect(
        zapReceipt.isValid(
          nostrPubKey: 'testPubKey',
          recipientLnurl: 'testLnurl',
        ),
        isTrue,
      );
    });

    test('isValid returns false for invalid pubKey', () {
      final zapReceipt = ZapReceipt.fromEvent(
        receipt(
          pubKey: 'wrongPubKey',
          tags: [
            ['bolt11', 'lnbc15u1p'],
            [
              'description',
              jsonEncode({
                'pubkey': 'testSender',
                'kind': ZapRequest.kZapRequestKind,
                'sig': "sig",
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'content': '',
                'tags': [
                  ['lnurl', 'testLnurl'],
                  ['amount', '1500000'],
                ],
              }),
            ],
          ],
        ),
      );
      expect(
        zapReceipt.isValid(
          nostrPubKey: 'testPubKey',
          recipientLnurl: 'testLnurl',
        ),
        isFalse,
      );
    });

    test('isValid returns false for mismatched amount', () {
      final zapReceipt = ZapReceipt.fromEvent(
        receipt(
          tags: [
            ['bolt11', 'lnbc15u1p'],
            [
              'description',
              jsonEncode({
                'pubkey': 'testSender',
                'kind': ZapRequest.kZapRequestKind,
                'sig': "sig",
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'content': '',
                'tags': [
                  ['lnurl', 'testLnurl'],
                  ['amount', '2000000'],
                ],
              }),
            ],
          ],
        ),
      );
      expect(
        zapReceipt.isValid(
          nostrPubKey: 'testPubKey',
          recipientLnurl: 'testLnurl',
        ),
        isFalse,
      );
    });

    test('isValid returns false for mismatched lnurl', () {
      final zapReceipt = ZapReceipt.fromEvent(
        receipt(
          tags: [
            ['bolt11', 'lnbc15u1p'],
            [
              'description',
              jsonEncode({
                'pubkey': 'testSender',
                'kind': ZapRequest.kZapRequestKind,
                'sig': "sig",
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'content': '',
                'tags': [
                  ['lnurl', 'wrongLnurl'],
                  ['amount', '1500000'],
                ],
              }),
            ],
          ],
        ),
      );

      expect(
        zapReceipt.isValid(
          nostrPubKey: 'testPubKey',
          recipientLnurl: 'testLnurl',
        ),
        isFalse,
      );
    });
  });
}
