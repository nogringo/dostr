import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_zaps/ndk_zaps.dart';
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
      final transport = LnurlTransportHttpImpl(NdkHttp(client));
      final Lnurl lnurl = Lnurl(transport: transport);

      var lnurlResponse = await lnurl.getLnurlResponse(link);
      expect(lnurlResponse, isNotNull);
      expect(lnurlResponse!.callback, response['callback']);
    });

    test('getLnurlResponse returns null for invalid link', () async {
      final client = MockClient((_) async => http.Response('not found', 404));
      final transport = LnurlTransportHttpImpl(NdkHttp(client));
      final Lnurl lnurl = Lnurl(transport: transport);

      final link = 'https://invalid.com';

      var lnurlResponse = await lnurl.getLnurlResponse(link);
      expect(lnurlResponse, isNull);
    });

    test('getAmountFromBolt11 returns correct amount for valid input', () {
      final amount = Lnurl.getAmountFromBolt11(
        'lnbc15u1p3xnhl2pp5jptserfk3zk4qy42tlucycrfwxhydvlemu9pqr93tuzlv9cc7g3sdqsvfhkcap3xyhx7un8cqzpgxqzjcsp5f8c52y2stc300gl6s4xswtjpc37hrnnr3c9wvtgjfuvqmpm35evq9qyyssqy4lgd8tj637qcjp05rdpxxykjenthxftej7a2zzmwrmrl70fyj9hvj0rewhzj7jfyuwkwcg9g2jpwtk3wkjtwnkdks84hsnu8xps5vsq4gj5hs',
      ); // Replace with a valid Bolt11 string
      expect(amount, 1500); // Replace with the expected amount
    });

    test('getAmountFromBolt11 returns null for invalid input', () {
      final amount = Lnurl.getAmountFromBolt11('invalid_bolt11_string');
      expect(amount, 0);
    });
  });
}
