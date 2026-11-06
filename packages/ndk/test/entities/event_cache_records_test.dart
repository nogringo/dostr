import 'package:ndk/entities.dart';
import 'package:test/test.dart';

void main() {
  group('EventCacheStateRecord', () {
    test('derives coordinate and expiration fields for addressable events', () {
      final event = Nip01Event(
        id: 'event-1',
        pubKey: 'pubkey-1',
        createdAt: 1700000000,
        kind: 30023,
        tags: const [
          ['d', 'article-1'],
          ['expiration', '1700009999'],
        ],
        content: 'hello',
        sig: 'sig-1',
      );

      final record = EventCacheStateRecord.buildForEvents([
        event,
      ], now: 1700000100).single;

      expect(record.eventId, event.id);
      expect(record.coordinateKey, '30023:pubkey-1:article-1');
      expect(record.expirationAt, 1700009999);
      expect(record.isCurrent, isTrue);
      expect(record.deletedByEventId, isNull);
    });

    test('round trips through json', () {
      const original = EventCacheStateRecord(
        eventId: 'event-2',
        pubKey: 'pubkey-2',
        kind: 1,
        createdAt: 1700000001,
        coordinateKey: null,
        isCurrent: false,
        expirationAt: 1700009999,
        deletedByEventId: 'delete-1',
      );

      final restored = EventCacheStateRecord.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.isDeleted, isTrue);
    });

    test('uses lower event id as tie breaker for addressable winners', () {
      final records = EventCacheStateRecord.buildForEvents([
        Nip01Event(
          id: 'bbbb',
          pubKey: 'pubkey-3',
          createdAt: 1700000002,
          kind: 30023,
          tags: const [
            ['d', 'article-1'],
          ],
          content: 'older',
          sig: 'sig-3',
        ),
        Nip01Event(
          id: 'aaaa',
          pubKey: 'pubkey-3',
          createdAt: 1700000002,
          kind: 30023,
          tags: const [
            ['d', 'article-1'],
          ],
          content: 'newer',
          sig: 'sig-4',
        ),
      ]);

      final byId = {for (final record in records) record.eventId: record};
      expect(byId['aaaa']!.isCurrent, isTrue);
      expect(byId['bbbb']!.isCurrent, isFalse);
    });
  });
}
