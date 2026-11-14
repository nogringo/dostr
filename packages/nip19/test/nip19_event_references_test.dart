import 'package:test/test.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip19/dostr_nip19.dart';

void main() {
  group('Nip01Event NIP-19 references', () {
    group('nevent', () {
      test('should encode regular event as nevent', () {
        final event = Nip01Event(
          pubKey:
              '76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa',
          kind: 1,
          tags: [],
          content: 'Hello Nostr!',
          createdAt: 1234567890,
        );

        final nevent = event.nevent();

        expect(nevent.startsWith('nevent1'), true);

        // Verify we can decode it back
        final decoded = Nevent.decode(nevent);
        expect(decoded.eventId, event.id);
        expect(decoded.author, event.pubKey);
        expect(decoded.kind, event.kind);
      });

      test('should use the given relays as hints', () {
        final event = Nip01Event(
          pubKey:
              '76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa',
          kind: 1,
          tags: [],
          content: 'Hello Nostr!',
          createdAt: 1234567890,
        );
        const relays = ['wss://relay.example.org/', 'wss://relay.primal.net/'];

        final nevent = event.nevent(relays: relays);

        final decoded = Nevent.decode(nevent);
        expect(decoded.relays, relays);
      });

      test('should not include relays if none are given', () {
        final event = Nip01Event(
          pubKey:
              '76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa',
          kind: 1,
          tags: [],
          content: 'Hello Nostr!',
          createdAt: 1234567890,
        );
        final nevent = event.nevent();

        final decoded = Nevent.decode(nevent);
        expect(decoded.relays, isEmpty);
      });
    });

    group('naddr', () {
      test('should encode parameterized replaceable event as naddr', () {
        final event = Nip01Event(
          pubKey:
              '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c',
          kind: 30023,
          tags: [
            ['d', 'my-article'],
          ],
          content: 'Article content',
          createdAt: 1234567890,
        );
        final naddr = event.naddr();

        expect(naddr, isNotNull);
        expect(naddr!.startsWith('naddr1'), true);

        // Verify we can decode it back
        final decoded = Naddr.decode(naddr);
        expect(decoded.identifier, 'my-article');
        expect(decoded.pubkey, event.pubKey);
        expect(decoded.kind, event.kind);
      });

      test('gives a replaceable event an empty identifier', () {
        for (final kind in [0, 3, 10002]) {
          final event = Nip01Event(
            pubKey:
                '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c',
            kind: kind,
            tags: [
              ['d', 'ignored'],
            ],
            content: '{"name":"Alice"}',
            createdAt: 1234567890,
          );

          final decoded = Naddr.decode(event.naddr()!);
          expect(decoded.identifier, '', reason: 'kind $kind');
          expect(decoded.kind, kind);
        }
      });

      test('gives a replaceable event without a d tag an naddr', () {
        final event = Nip01Event(
          pubKey:
              '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c',
          kind: 0,
          tags: [],
          content: '{"name":"Alice"}',
          createdAt: 1234567890,
        );

        expect(Naddr.decode(event.naddr()!).identifier, '');
      });

      test('should return null for non-addressable event', () {
        final event = Nip01Event(
          pubKey:
              '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c',
          kind: 1, // Regular text note, not addressable
          tags: [
            ['d', 'test'],
          ],
          content: 'Hello',
          createdAt: 1234567890,
        );
        final naddr = event.naddr();

        expect(naddr, isNull);
      });

      test('should return null for addressable event without d tag', () {
        final event = Nip01Event(
          pubKey:
              '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c',
          kind: 30023,
          tags: [], // No d tag
          content: 'Article content',
          createdAt: 1234567890,
        );
        final naddr = event.naddr();

        expect(naddr, isNull);
      });

      test('should use the given relays as hints', () {
        final event = Nip01Event(
          pubKey:
              '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c',
          kind: 31990,
          tags: [
            ['d', '1685802317447'],
          ],
          content: '{}',
          createdAt: 1234567890,
        );
        const relays = ['wss://relay.example.com'];

        final naddr = event.naddr(relays: relays);

        expect(naddr, isNotNull);
        final decoded = Naddr.decode(naddr!);
        expect(decoded.relays, relays);
      });
    });

    group('addressable kinds', () {
      const testPubkey =
          '460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c';

      test('should recognize replaceable event kinds', () {
        final kinds = [0, 3, 41];
        for (final kind in kinds) {
          final event = Nip01Event(
            pubKey: testPubkey,
            kind: kind,
            tags: [
              ['d', ''],
            ],
            content: '',
          );

          expect(
            event.naddr(),
            isNotNull,
            reason: 'Kind $kind should be addressable',
          );
        }
      });

      test('should recognize parameterized replaceable event kinds', () {
        final kinds = [30000, 35000, 39999];
        for (final kind in kinds) {
          final event = Nip01Event(
            pubKey: testPubkey,
            kind: kind,
            tags: [
              ['d', 'test'],
            ],
            content: '',
          );

          expect(
            event.naddr(),
            isNotNull,
            reason: 'Kind $kind should be addressable',
          );
        }
      });

      test('should not recognize non-addressable kinds', () {
        final kinds = [1, 2, 4, 5, 6, 7, 40, 42, 9999, 20000, 29999, 40000];
        for (final kind in kinds) {
          final event = Nip01Event(
            pubKey: testPubkey,
            kind: kind,
            tags: [
              ['d', 'test'],
            ],
            content: '',
          );
          expect(
            event.naddr(),
            isNull,
            reason: 'Kind $kind should not be addressable',
          );
        }
      });
    });
  });
}
