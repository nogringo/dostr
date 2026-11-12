import 'package:dostr_cashu_protocol/dostr_cashu_protocol.dart';
import 'package:test/test.dart';

// NUT-00 TokenV4 example
const nut00Token =
    'cashuBo2F0gqJhaUgA_9SLj17PgGFwgaNhYQFhc3hAYWNjMTI0MzVlN2I4NDg0YzNjZjE4NTAxNDkyMThhZjkwZjcxNmE1MmJmNGE1ZWQzNDdlNDhlY2MxM2Y3NzM4OGFjWCECRFODGd5IXVW-07KaZCvuWHk3WrnnpiDhHki6SCQh88-iYWlIAK0mjE0fWCZhcIKjYWECYXN4QDEzMjNkM2Q0NzA3YTU4YWQyZTIzYWRhNGU5ZjFmNDlmNWE1YjRhYzdiNzA4ZWIwZDYxZjczOGY0ODMwN2U4ZWVhY1ghAjRWqhENhLSsdHrr2Cw7AFrKUL9Ffr1XN6RBT6w659lNo2FhAWFzeEA1NmJjYmNiYjdjYzY0MDZiM2ZhNWQ1N2QyMTc0ZjRlZmY4YjQ0MDJiMTc2OTI2ZDNhNTdkM2MzZGNiYjU5ZDU3YWNYIQJzEpxXGeWZN5qXSmJjY8MzxWyvwObQGr5G1YCCgHicY2FtdWh0dHA6Ly9sb2NhbGhvc3Q6MzMzOGF1Y3NhdA';

void main() {
  group('CashuTokenEncoder', () {
    test('decodes the NUT-00 v4 token with lowercase hex', () {
      final token = CashuTokenEncoder.decodedToken(nut00Token)!;

      expect(token.mintUrl, 'http://localhost:3338');
      expect(token.unit, 'sat');
      expect(token.memo, '');
      expect(token.proofs.map((proof) => proof.keysetId), [
        '00ffd48b8f5ecf80',
        '00ad268c4d1f5826',
        '00ad268c4d1f5826',
      ]);
      expect(token.proofs.map((proof) => proof.amount), [1, 2, 1]);
      expect(
        token.proofs.first.secret,
        'acc12435e7b8484c3cf1850149218af90f716a52bf4a5ed347e48ecc13f77388',
      );
      expect(token.proofs.map((proof) => proof.unblindedSig), [
        '0244538319de485d55bed3b29a642bee5879375ab9e7a620e11e48ba482421f3cf',
        '023456aa110d84b4ac747aebd82c3b005aca50bf457ebd5737a4414fac3ae7d94d',
        '0273129c5719e599379a974a626363c333c56cafc0e6d01abe46d5808280789c63',
      ]);
    });

    test('decodes what it encodes', () {
      final token = CashuTokenEncoder.decodedToken(nut00Token)!;
      final withMemo = CashuToken(
        proofs: token.proofs,
        memo: 'Thank you',
        unit: token.unit,
        mintUrl: token.mintUrl,
      );

      final decoded = CashuTokenEncoder.decodedToken(
        withMemo.toV4TokenString(),
      )!;

      expect(decoded.memo, 'Thank you');
      expect(decoded.mintUrl, token.mintUrl);
      expect(
        decoded.proofs.map((proof) => proof.toJson()),
        token.proofs.map((proof) => proof.toJson()),
      );
    });

    test('returns null for what is not a v4 token', () {
      expect(CashuTokenEncoder.decodedToken('cashuAeyJ0b2tlbiI6W119'), isNull);
      expect(CashuTokenEncoder.decodedToken('cashuB!!!'), isNull);
      expect(CashuTokenEncoder.decodedToken(''), isNull);
    });
  });
}
