import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_requests/ndk_requests.dart';
import 'package:test/test.dart';

void main() {
  group('FilterFingerprint', () {
    test('generates same hash for identical filters', () {
      final filter1 = Filter(kinds: [1], authors: ['pubkey1', 'pubkey2']);
      final filter2 = Filter(kinds: [1], authors: ['pubkey1', 'pubkey2']);

      final hash1 = FilterFingerprint.generate(filter1);
      final hash2 = FilterFingerprint.generate(filter2);

      expect(hash1, equals(hash2));
    });

    test('generates same hash regardless of author order', () {
      final filter1 = Filter(kinds: [1], authors: ['pubkey1', 'pubkey2']);
      final filter2 = Filter(kinds: [1], authors: ['pubkey2', 'pubkey1']);

      final hash1 = FilterFingerprint.generate(filter1);
      final hash2 = FilterFingerprint.generate(filter2);

      expect(hash1, equals(hash2));
    });

    test('ignores since/until/limit in hash', () {
      final filter1 = Filter(kinds: [1], authors: ['pubkey1']);
      final filter2 = Filter(
        kinds: [1],
        authors: ['pubkey1'],
        since: 1704067200,
        until: 1704153600,
        limit: 100,
      );

      final hash1 = FilterFingerprint.generate(filter1);
      final hash2 = FilterFingerprint.generate(filter2);

      expect(hash1, equals(hash2));
    });

    test('generates different hash for different filters', () {
      final filter1 = Filter(kinds: [1], authors: ['pubkey1']);
      final filter2 = Filter(kinds: [1], authors: ['pubkey2']);
      final filter3 = Filter(kinds: [0], authors: ['pubkey1']);

      final hash1 = FilterFingerprint.generate(filter1);
      final hash2 = FilterFingerprint.generate(filter2);
      final hash3 = FilterFingerprint.generate(filter3);

      expect(hash1, isNot(equals(hash2)));
      expect(hash1, isNot(equals(hash3)));
    });

    test('generateAsync produces same result as generate', () async {
      final filter = Filter(kinds: [1, 2], authors: ['pubkey1', 'pubkey2']);

      final syncHash = FilterFingerprint.generate(filter);
      final asyncHash = await FilterFingerprint.generateAsync(filter);

      expect(asyncHash, equals(syncHash));
    });
  });
}
