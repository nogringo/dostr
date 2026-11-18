import 'package:dostr_zaps/dostr_zaps.dart';
import 'package:test/test.dart';

void main() {
  group('bolt11AmountMsats', () {
    test('reads the amount of an invoice', () {
      expect(
        bolt11AmountMsats(
          'lnbc15u1p3xnhl2pp5jptserfk3zk4qy42tlucycrfwxhydvlemu9pqr93tuzlv9cc7g3sdqsvfhkcap3xyhx7un8cqzpgxqzjcsp5f8c52y2stc300gl6s4xswtjpc37hrnnr3c9wvtgjfuvqmpm35evq9qyyssqy4lgd8tj637qcjp05rdpxxykjenthxftej7a2zzmwrmrl70fyj9hvj0rewhzj7jfyuwkwcg9g2jpwtk3wkjtwnkdks84hsnu8xps5vsq4gj5hs',
        ),
        1500000,
      );
    });

    test('applies each multiplier', () {
      expect(bolt11AmountMsats('lnbc2m1pvjluez'), 200000000);
      expect(bolt11AmountMsats('lnbc25u1pvjluez'), 2500000);
      expect(bolt11AmountMsats('lnbc210n1pvjluez'), 21000);
      expect(bolt11AmountMsats('lnbc10p1pvjluez'), 1);
      expect(bolt11AmountMsats('lnbc21pvjluez'), 200000000000);
    });

    test('reads other networks and uppercase invoices', () {
      expect(bolt11AmountMsats('lntb20m1pvjluez'), 2000000000);
      expect(bolt11AmountMsats('lnbcrt50u1pvjluez'), 5000000);
      expect(bolt11AmountMsats('LNBC10U1P3UNWFU'), 1000000);
    });

    test('is null without amount', () {
      expect(bolt11AmountMsats('lnbc1pvjluez'), isNull);
    });

    test('is null for what is not an invoice', () {
      expect(bolt11AmountMsats('invalid_bolt11_string'), isNull);
      expect(bolt11AmountMsats('lnbc15x1pvjluez'), isNull);
      expect(bolt11AmountMsats(''), isNull);
    });

    test('is null for a fraction of a millisat', () {
      expect(bolt11AmountMsats('lnbc15p1pvjluez'), isNull);
    });

    test('is null beyond the bitcoin supply', () {
      expect(bolt11AmountMsats('lnbc210000001pvjluez'), 2100000000000000000);
      expect(bolt11AmountMsats('lnbc210000011pvjluez'), isNull);
      expect(bolt11AmountMsats('lnbc99999999999999999999m1pvjluez'), isNull);
    });
  });
}
