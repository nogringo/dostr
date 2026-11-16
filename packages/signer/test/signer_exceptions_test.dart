import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

void main() {
  group('SignerRequestRejectedException', () {
    test('toString with requestId and message', () {
      final e = SignerRequestRejectedException(
        requestId: 'req123',
        originalMessage: 'denied',
      );
      expect(e.toString(), contains('req123'));
      expect(e.toString(), contains('denied'));
    });

    test('toString with only requestId', () {
      final e = SignerRequestRejectedException(requestId: 'req456');
      expect(e.toString(), contains('req456'));
    });

    test('toString with only message', () {
      final e = SignerRequestRejectedException(originalMessage: 'error');
      expect(e.toString(), contains('error'));
    });

    test('toString with no params', () {
      final e = SignerRequestRejectedException();
      expect(e.toString(), contains('SignerRequestRejectedException'));
    });
  });

  group('SignerRequestCancelledException', () {
    test('toString formats correctly', () {
      final e = SignerRequestCancelledException('req789');
      expect(e.toString(), contains('req789'));
    });
  });

  group('SignerRequestFailedException', () {
    test('toString with requestId, message and cause', () {
      final e = SignerRequestFailedException(
        'invalid event',
        requestId: 'req321',
        cause: const FormatException('bad json'),
      );
      expect(e.toString(), contains('req321'));
      expect(e.toString(), contains('invalid event'));
      expect(e.toString(), contains('bad json'));
    });

    test('toString with only a message', () {
      final e = SignerRequestFailedException('no answer');
      expect(e.toString(), 'SignerRequestFailedException: no answer');
    });
  });

  test('all are a SignerRequestException with their requestId', () {
    final SignerRequestException rejected = SignerRequestRejectedException(
      requestId: 'req1',
    );
    final SignerRequestException cancelled = SignerRequestCancelledException(
      'req2',
    );
    final SignerRequestException failed = SignerRequestFailedException(
      'no answer',
      requestId: 'req3',
    );

    expect(rejected.requestId, 'req1');
    expect(cancelled.requestId, 'req2');
    expect(failed.requestId, 'req3');
    expect(SignerRequestRejectedException().requestId, isNull);
  });
}
