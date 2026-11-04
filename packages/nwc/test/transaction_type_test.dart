import 'package:ndk_nwc/ndk_nwc.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionType', () {
    test('fromValue returns incoming for unknown value', () {
      expect(TransactionType.fromValue('unknown'), TransactionType.incoming);
    });

    test('fromValue returns outgoing for outgoing value', () {
      expect(TransactionType.fromValue('outgoing'), TransactionType.outgoing);
    });

    test('fromValue returns incoming for incoming value', () {
      expect(TransactionType.fromValue('incoming'), TransactionType.incoming);
    });
  });
}
