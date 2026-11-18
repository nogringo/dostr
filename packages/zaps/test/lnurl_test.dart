import 'dart:convert';

import 'package:dostr_zaps/dostr_zaps.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('Lnurl', () {
    test('getLud16LinkFromLud16 returns correct URL', () {
      expect(
        Lnurl.getLud16LinkFromLud16('name@domain.com'),
        'https://domain.com/.well-known/lnurlp/name',
      );
    });

    test('getLud16LinkFromLud16 returns null for invalid input', () {
      expect(Lnurl.getLud16LinkFromLud16('invalid'), isNull);
    });

    test('getLnurlResponse returns LnurlResponse for valid link', () async {
      final link = 'https://domain.com/.well-known/lnurlp/name';
      final response = {
        'callback': 'https://domain.com/callback',
        'commentAllowed': 100,
      };
      final client = MockClient((request) async {
        if (request.url == Uri.parse(link) &&
            request.headers['Accept'] == 'application/json') {
          return http.Response(jsonEncode(response), 200);
        }
        return http.Response('unexpected request', 500);
      });
      final transport = HttpLnurlTransport(client);
      final Lnurl lnurl = Lnurl(transport: transport);

      var lnurlResponse = await lnurl.getLnurlResponse(link);
      expect(lnurlResponse, isNotNull);
      expect(lnurlResponse!.callback, response['callback']);
    });

    test('getLnurlResponse returns null for invalid link', () async {
      final client = MockClient((_) async => http.Response('not found', 404));
      final transport = HttpLnurlTransport(client);
      final Lnurl lnurl = Lnurl(transport: transport);

      final link = 'https://invalid.com';

      var lnurlResponse = await lnurl.getLnurlResponse(link);
      expect(lnurlResponse, isNull);
    });

    test('getLnurlResponse returns null without a callback', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'status': 'ERROR', 'reason': 'unknown user'}),
          200,
        ),
      );
      final lnurl = Lnurl(transport: HttpLnurlTransport(client));

      expect(await lnurl.getLnurlResponse('https://domain.com'), isNull);
    });
  });

  group('LnurlResponse.fromJson', () {
    test('reads the NIP-57 fields', () {
      final response = LnurlResponse.fromJson({
        'callback': 'https://domain.com/callback',
        'minSendable': 1000,
        'maxSendable': 100000000,
        'commentAllowed': 255,
        'tag': 'payRequest',
        'allowsNostr': true,
        'nostrPubkey': 'serverPubkey',
      });

      expect(response.callback, 'https://domain.com/callback');
      expect(response.minSendable, 1000);
      expect(response.maxSendable, 100000000);
      expect(response.commentAllowed, 255);
      expect(response.tag, 'payRequest');
      expect(response.allowsNostr, isTrue);
      expect(response.nostrPubkey, 'serverPubkey');
    });

    test('reads a field of the wrong type as null', () {
      final response = LnurlResponse.fromJson({
        'callback': 'https://domain.com/callback',
        'commentAllowed': '255',
        'allowsNostr': 'true',
      });

      expect(response.commentAllowed, isNull);
      expect(response.allowsNostr, isFalse);
    });

    test('throws a FormatException without a callback', () {
      expect(
        () => LnurlResponse.fromJson({'status': 'ERROR'}),
        throwsFormatException,
      );
    });
  });
}
