import 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:test/test.dart';

void main() {
  group('EventDeliveryRecord', () {
    test('round trips through json', () {
      final original = EventDeliveryRecord(
        eventId: 'event-3',
        status: EventDeliveryStatus.partiallyDelivered,
        signingState: EventSigningState.transientFailure,
        createdAt: 1700001000,
        updatedAt: 1700001010,
        signedAt: 1700001005,
        completedAt: 1700001020,
        requiresInteractiveSigning: true,
        signAttemptCount: 2,
        lastSignAttemptAt: 1700001008,
        nextSignRetryAt: 1700001100,
        lastSignError: 'timed out',
        unresolvedUrlSets: const [
          UnresolvedUrlSet(
            urlSet: UrlSet.first(5, UrlSet.inbox('bob')),
            authCanonical: 'never',
          ),
        ],
      );

      final restored = EventDeliveryRecord.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.isComplete, isFalse);
    });

    test('a record stored before unresolved url sets has none', () {
      final json = EventDeliveryRecord(
        eventId: 'event-3',
        createdAt: 1700001000,
        updatedAt: 1700001010,
      ).toJson()..remove('unresolvedUrlSets');

      expect(EventDeliveryRecord.fromJson(json).unresolvedUrlSets, isEmpty);
    });
  });

  group('RelayDeliveryTarget', () {
    test('round trips through json', () {
      const original = RelayDeliveryTarget(
        eventId: 'event-4',
        relayUrl: 'wss://relay.two',
        reason: RelayDeliveryReason.explicit,
        state: RelayDeliveryState.transientFailure,
        attemptCount: 2,
        nextRetryAt: 1700003000,
        lastError: 'timeout',
      );

      final restored = RelayDeliveryTarget.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.key, 'event-4|wss://relay.two');
    });

    test('copyWith can clear nullable retry metadata fields', () {
      const original = RelayDeliveryTarget(
        eventId: 'event-4',
        relayUrl: 'wss://relay.two',
        reason: RelayDeliveryReason.explicit,
        state: RelayDeliveryState.transientFailure,
        attemptCount: 2,
        lastAttemptAt: 1700002000,
        nextRetryAt: 1700003000,
        lastError: 'timeout',
        lastOkMessage: 'ok',
      );

      final cleared = original.copyWith(
        nextRetryAt: null,
        lastError: null,
        lastOkMessage: null,
      );

      expect(cleared.nextRetryAt, isNull);
      expect(cleared.lastError, isNull);
      expect(cleared.lastOkMessage, isNull);
      expect(cleared.lastAttemptAt, original.lastAttemptAt);
    });
  });
}
