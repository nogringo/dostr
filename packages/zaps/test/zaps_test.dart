import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_zaps/ndk_zaps.dart';
import 'package:test/test.dart';

import 'mocks/fake_network.dart';
import 'mocks/mock_slow_signer.dart';

void main() {
  EventSigner eventSignerFactory({
    String? privateKey,
    required String publicKey,
  }) => Bip340EventSigner(privateKey: privateKey, publicKey: publicKey);

  Zaps zapsFor(FakeRelays relays, {http.Client? client}) => Zaps(
    query: relays.query,
    subscribe: relays.subscribe,
    lnurl: Lnurl(
      transport: LnurlTransportHttpImpl(
        NdkHttp(
          client ?? MockClient((_) async => http.Response('not found', 404)),
        ),
      ),
    ),
  );

  group('Zaps', () {
    KeyPair key = Bip340.generatePrivateKey();
    late FakeRelays relays;
    late Zaps zaps;

    setUp(() {
      relays = FakeRelays();
      zaps = zapsFor(relays);
    });

    test('fetchInvoice returns invoice code for valid input', () async {
      final response = {
        'callback': 'https://domain.com/callback',
        'commentAllowed': 100,
        'allowsNostr': true,
      };
      final link = 'https://domain.com/.well-known/lnurlp/name';
      final client = MockClient((request) async {
        if (request.headers['Accept'] != 'application/json') {
          return http.Response('unexpected request', 500);
        }
        if (request.url == Uri.parse(link)) {
          return http.Response(jsonEncode(response), 200);
        }
        if (request.url.toString().startsWith('https://domain.com/callback')) {
          return http.Response(
            jsonEncode({
              "status": "OK",
              "successAction": {
                "tag": "message",
                "message": "Payment Received!",
              },
              "routes": [],
              "pr": "lnbc1000....",
            }),
            200,
          );
        }
        return http.Response('unexpected request', 500);
      });
      final amount = 1000;

      final zaps = zapsFor(relays, client: client);

      ZapRequest zapRequest = await zaps.createZapRequest(
        amountSats: amount,
        eventId: 'eventId',
        comment: 'comment',
        signer: eventSignerFactory(
          privateKey: key.privateKey,
          publicKey: key.publicKey,
        ),
        pubKey: 'pubKey',
        relays: ['relay1', 'relay2'],
      );

      var invoiceResponse = await zaps.fetchInvoice(
        lud16Link: link,
        amountSats: amount,
        zapRequest: zapRequest,
      );
      expect(invoiceResponse!.amountSats, amount);
      expect(invoiceResponse.invoice, startsWith("lnbc$amount"));
    });

    test('fetchInvoice returns null for invalid input', () async {
      var invoiceCode = await zaps.fetchInvoice(
        lud16Link: 'invalid',
        amountSats: 1000,
      );
      expect(invoiceCode, isNull);
    });

    test('zapRequest returns valid ZapRequest for correct inputs', () async {
      final amount = 1000;
      final eventId = 'eventId';
      final comment = 'comment';
      final pubKey = 'pubKey';
      final relays = ['relay1', 'relay2'];
      ZapRequest zapRequest = await zaps.createZapRequest(
        amountSats: amount,
        eventId: eventId,
        comment: comment,
        signer: eventSignerFactory(
          privateKey: key.privateKey,
          publicKey: key.publicKey,
        ),
        pubKey: pubKey,
        relays: relays,
      );

      expect(zapRequest, isNotNull);
      expect(
        zapRequest.tags,
        containsAll([
          ['amount', (amount * 1000).toString()],
          ['e', eventId],
          ['p', pubKey],
          ['relays', ...relays],
        ]),
      );
      expect(zapRequest.content, comment);
      expect(zapRequest.sig, isNotNull);
    });

    test(
      'zapRequest from a slow signer has a valid id and signature',
      () async {
        ZapRequest zapRequest = await zaps.createZapRequest(
          amountSats: 1000,
          eventId: 'eventId',
          comment: 'comment',
          signer: MockSlowSigner(
            innerSigner: eventSignerFactory(
              privateKey: key.privateKey,
              publicKey: key.publicKey,
            ),
            delay: const Duration(milliseconds: 1100),
          ),
          pubKey: 'pubKey',
          relays: ['relay1'],
        );

        expect(zapRequest.hasValidId, isTrue);
        expect(
          Bip340.verify(zapRequest.id, zapRequest.sig!, zapRequest.pubKey),
          isTrue,
        );
      },
    );

    test('zapRequest throws error for negative amount', () async {
      expect(
        () async => await zaps.createZapRequest(
          amountSats: -1000,
          eventId: 'eventId',
          comment: 'comment',
          signer: eventSignerFactory(
            privateKey: key.privateKey,
            publicKey: key.publicKey,
          ),
          pubKey: 'pubKey',
          relays: ['relay1', 'relay2'],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('zapRequest handles empty relays list', () async {
      ZapRequest zapRequest = await zaps.createZapRequest(
        amountSats: 1000,
        eventId: 'eventId',
        comment: 'comment',
        signer: eventSignerFactory(
          privateKey: key.privateKey,
          publicKey: key.publicKey,
        ),
        pubKey: 'pubKey',
        relays: [],
      );

      expect(zapRequest, isNotNull);
    });

    test('ZapRequest.nip01Event keeps a zap request as it is', () {
      final event = ZapRequest(
        pubKey: key.publicKey,
        tags: [],
        content: '',
      ).copyWith(sig: 'f' * 128);

      final zapRequest = ZapRequest.nip01Event(event: event);

      expect(zapRequest.id, event.id);
      expect(zapRequest.sig, event.sig);
    });

    test('ZapRequest.nip01Event gives another kind a new id and no sig', () {
      final note = Nip01Event(
        pubKey: key.publicKey,
        kind: 1,
        tags: [],
        content: '',
      ).copyWith(sig: 'f' * 128);

      final zapRequest = ZapRequest.nip01Event(event: note);

      expect(zapRequest.kind, ZapRequest.kZapRequestKind);
      expect(zapRequest.hasValidId, isTrue);
      expect(zapRequest.sig, isNull);
    });

    Nip01Event receipt(String recipient, String bolt11) => Nip01Event(
      pubKey: key.publicKey,
      kind: ZapReceipt.kKind,
      tags: [
        ['p', recipient],
        ['bolt11', bolt11],
      ],
      content: '',
    );

    test('fetchZappedReceipts queries the receipts of an event', () async {
      relays.events.add(receipt('recipient', 'lnbc21u1p'));

      final receipts = await zaps
          .fetchZappedReceipts(pubKey: 'recipient', eventId: 'eventId')
          .toList();

      expect(receipts.single.recipient, 'recipient');
      expect(receipts.single.amountSats, 2100);
      final query = relays.queries.single;
      expect(query.filter.kinds, [ZapReceipt.kKind]);
      expect(query.filter.pTags, ['recipient']);
      expect(query.filter.eTags, ['eventId']);
      expect(query.filter.aTags, isNull);
      expect(query.timeout, const Duration(seconds: 10));
    });

    test('fetchZappedReceipts passes its timeout and addressable id', () async {
      await zaps
          .fetchZappedReceipts(
            pubKey: 'recipient',
            addressableId: '30023:pubkey:d',
            timeout: const Duration(seconds: 3),
          )
          .toList();

      final query = relays.queries.single;
      expect(query.filter.aTags, ['30023:pubkey:d']);
      expect(query.filter.eTags, isNull);
      expect(query.timeout, const Duration(seconds: 3));
    });

    test('subscribeToZapReceipts streams receipts until closed', () async {
      final subscription = zaps.subscribeToZapReceipts(pubKey: 'recipient');
      final events = subscription.events.toList();

      relays.push(receipt('recipient', 'lnbc1u1p'));
      await subscription.close();

      expect((await events).single.getFirstTag('p'), 'recipient');
      expect(relays.subscriptions.single.kinds, [ZapReceipt.kKind]);
      expect(relays.subscriptions.single.pTags, ['recipient']);
      expect(relays.closed, 1);
    });
  });
}
