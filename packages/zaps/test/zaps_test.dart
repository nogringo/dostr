import 'dart:convert';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_zaps/dostr_zaps.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'mocks/fake_network.dart';
import 'mocks/mock_slow_signer.dart';

void main() {
  final relay1 = RelayUrl.parse('wss://relay1.example.com');
  final relay2 = RelayUrl.parse('wss://relay2.example.com');

  Zaps zapsFor(FakeRelays relays, {http.Client? client}) => Zaps(
    query: relays.query,
    subscribe: relays.subscribe,
    lnurl: Lnurl(
      transport: HttpLnurlTransport(
        client ?? MockClient((_) async => http.Response('not found', 404)),
      ),
    ),
  );

  group('Zaps', () {
    KeyPair key = Bip340.generateKeyPair();
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
        signer: Bip340Signer(key.privateKey),
        pubkey: 'pubkey',
        relays: [relay1, relay2],
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

    test('fetchInvoice sends the comment to the callback', () async {
      final link = 'https://domain.com/.well-known/lnurlp/name';
      Uri? callback;
      final client = MockClient((request) async {
        if (request.url == Uri.parse(link)) {
          return http.Response(
            jsonEncode({
              'callback': 'https://domain.com/callback',
              'commentAllowed': 100,
            }),
            200,
          );
        }
        callback = request.url;
        return http.Response(jsonEncode({'pr': 'lnbc210n1p'}), 200);
      });

      final invoice = await zapsFor(
        relays,
        client: client,
      ).fetchInvoice(lud16Link: link, amountSats: 21, comment: 'thanks!');

      expect(invoice, isNotNull);
      expect(callback!.queryParameters['comment'], 'thanks!');
      expect(callback!.queryParameters['amount'], '21000');
    });

    test('zapRequest returns valid ZapRequest for correct inputs', () async {
      final amount = 1000;
      final eventId = 'eventId';
      final comment = 'comment';
      final pubkey = 'pubkey';
      final relays = [relay1, relay2];
      ZapRequest zapRequest = await zaps.createZapRequest(
        amountSats: amount,
        eventId: eventId,
        comment: comment,
        signer: Bip340Signer(key.privateKey),
        pubkey: pubkey,
        relays: relays,
      );

      expect(zapRequest, isNotNull);
      expect(
        zapRequest.tags,
        containsAll([
          ['amount', (amount * 1000).toString()],
          ['e', eventId],
          ['p', pubkey],
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
            innerSigner: Bip340Signer(key.privateKey),
            delay: const Duration(milliseconds: 1100),
          ),
          pubkey: 'pubkey',
          relays: [relay1],
        );

        expect(zapRequest.hasValidId, isTrue);
        expect(
          Bip340.verify(
            message: zapRequest.id,
            signature: zapRequest.sig!,
            publicKey: zapRequest.pubkey,
          ),
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
          signer: Bip340Signer(key.privateKey),
          pubkey: 'pubkey',
          relays: [relay1, relay2],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('zapRequest handles empty relays list', () async {
      ZapRequest zapRequest = await zaps.createZapRequest(
        amountSats: 1000,
        eventId: 'eventId',
        comment: 'comment',
        signer: Bip340Signer(key.privateKey),
        pubkey: 'pubkey',
        relays: [],
      );

      expect(zapRequest, isNotNull);
    });

    test('ZapRequest.nip01Event keeps a zap request as it is', () {
      final event = ZapRequest(
        pubkey: key.publicKey,
        tags: [],
        content: '',
      ).copyWith(sig: 'f' * 128);

      final zapRequest = ZapRequest.nip01Event(event: event);

      expect(zapRequest.id, event.id);
      expect(zapRequest.sig, event.sig);
    });

    test('ZapRequest.nip01Event gives another kind a new id and no sig', () {
      final note = Nip01Event(
        pubkey: key.publicKey,
        kind: 1,
        tags: [],
        content: '',
      ).copyWith(sig: 'f' * 128);

      final zapRequest = ZapRequest.nip01Event(event: note);

      expect(zapRequest.kind, ZapRequest.kZapRequestKind);
      expect(zapRequest.hasValidId, isTrue);
      expect(zapRequest.sig, isNull);
    });

    const server = 'serverPubkey';

    /// A receipt of [server] for a zap of 21 sats to [recipient], whose
    /// invoice is [bolt11].
    Nip01Event receipt({
      String pubkey = server,
      String recipient = 'recipient',
      String bolt11 = 'lnbc21u1p',
      List<List<String>> tags = const [],
    }) => Nip01Event(
      pubkey: pubkey,
      kind: ZapReceipt.kKind,
      tags: [
        ['p', recipient],
        ['bolt11', bolt11],
        [
          'description',
          jsonEncode({
            'pubkey': key.publicKey,
            'kind': ZapRequest.kZapRequestKind,
            'created_at': 1234567880,
            'content': '',
            'tags': [
              ['p', recipient],
              ['amount', '2100000'],
            ],
          }),
        ],
        ...tags,
      ],
      content: '',
    );

    test('fetchZappedReceipts asks the receipts the server signed', () async {
      relays.events.add(
        receipt(
          tags: [
            ['e', 'eventId'],
          ],
        ),
      );

      final receipts = await zaps
          .fetchZappedReceipts(
            pubkey: 'recipient',
            nostrPubkey: server,
            eventId: 'eventId',
          )
          .toList();

      expect(receipts.single.recipient, 'recipient');
      expect(receipts.single.amountSats, 2100);
      final query = relays.queries.single;
      expect(query.filter.kinds, [ZapReceipt.kKind]);
      expect(query.filter.authors, [server]);
      expect(query.filter.pTags, ['recipient']);
      expect(query.filter.eTags, ['eventId']);
      expect(query.filter.aTags, isNull);
      expect(query.timeout, const Duration(seconds: 10));
    });

    test('fetchZappedReceipts drops the receipts that are not valid', () async {
      relays.events.addAll([
        receipt(),
        receipt(pubkey: 'otherServer'),
        receipt(recipient: 'someoneElse'),
        receipt(bolt11: 'lnbc1u1p'),
      ]);

      final receipts = await zaps
          .fetchZappedReceipts(pubkey: 'recipient', nostrPubkey: server)
          .toList();

      expect(receipts.single.amountMsats, 2100000);
    });

    test('fetchZappedReceipts passes its timeout and addressable id', () async {
      await zaps
          .fetchZappedReceipts(
            pubkey: 'recipient',
            nostrPubkey: server,
            addressableId: '30023:pubkey:d',
            timeout: const Duration(seconds: 3),
          )
          .toList();

      final query = relays.queries.single;
      expect(query.filter.aTags, ['30023:pubkey:d']);
      expect(query.filter.eTags, isNull);
      expect(query.timeout, const Duration(seconds: 3));
    });

    test(
      'subscribeToZapReceipts streams valid receipts until closed',
      () async {
        final subscription = zaps.subscribeToZapReceipts(
          pubkey: 'recipient',
          nostrPubkey: server,
        );
        final receipts = subscription.receipts.toList();

        relays.push(receipt(pubkey: 'otherServer'));
        relays.push(receipt());
        await subscription.close();

        expect((await receipts).single.pubkey, server);
        expect(relays.subscriptions.single.kinds, [ZapReceipt.kKind]);
        expect(relays.subscriptions.single.authors, [server]);
        expect(relays.subscriptions.single.pTags, ['recipient']);
        expect(relays.closed, 1);
      },
    );
  });
}
