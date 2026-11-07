import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:test/test.dart';

void main() {
  group('DeliveryPolicy', () {
    test('uses latest-state-only policy for replaceable events', () {
      final event = Nip01Event(
        id: 'replaceable-1',
        pubKey: 'pubkey',
        createdAt: 1700000000,
        kind: 30023,
        tags: const [
          ['d', 'article-1'],
        ],
        content: 'article',
        sig: 'sig',
      );

      final policy = DeliveryPolicy.forEvent(event);

      expect(policy.kind, DeliveryPolicyKind.latestStateOnly);
      expect(policy.retainsOnlyLatest, isTrue);
    });

    test(
      'uses latest-state-only policy for regular replaceable events too',
      () {
        final event = Nip01Event(
          id: 'replaceable-2',
          pubKey: 'pubkey',
          createdAt: 1700000000,
          kind: 10002,
          tags: const [],
          content: 'relay list',
          sig: 'sig',
        );

        final policy = DeliveryPolicy.forEvent(event);

        expect(policy.kind, DeliveryPolicyKind.latestStateOnly);
        expect(policy.retainsOnlyLatest, isTrue);
      },
    );

    test('uses do-not-retry policy for ephemeral events', () {
      final event = Nip01Event(
        id: 'ephemeral-1',
        pubKey: 'pubkey',
        createdAt: 1700000001,
        kind: 24133,
        tags: const [],
        content: 'ephemeral',
        sig: 'sig',
      );

      final policy = DeliveryPolicy.forEvent(event);

      expect(policy.kind, DeliveryPolicyKind.doNotRetry);
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'rate-limited: retry later',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
    });

    test('auth-required under never is permanent, not retryable', () {
      final event = Nip01Event(
        id: 'event-never',
        pubKey: 'pubkey',
        createdAt: 1700000002,
        kind: Nip01Event.kTextNoteKind,
        tags: const [],
        content: 'text',
        sig: 'sig',
      );

      final policy = DeliveryPolicy.forEvent(event);
      final refusal = DeliveryResponse(
        relayUrl: 'wss://relay.example',
        message: 'auth-required: please authenticate',
      );

      // no identity may ever be revealed here, so retrying every minute could
      // only ever collect the same refusal
      expect(
        policy.resolveNextState(refusal, auth: const AuthPolicy.never()),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.resolveNextState(refusal),
        RelayDeliveryState.authRequired,
        reason: 'a broadcast that named nobody may still authenticate',
      );
    });

    test('classifies a failure by identityNotAllowed, not by its text', () {
      Nip01Event eventOfKind(int kind) => Nip01Event(
        id: 'event-$kind',
        pubKey: 'pubkey',
        createdAt: 1700000002,
        kind: kind,
        tags: const [],
        content: 'text',
        sig: 'sig',
      );
      DeliveryResponse failed(
        String failure, {
        bool identityNotAllowed = false,
      }) => DeliveryResponse(
        relayUrl: 'wss://relay.example',
        failure: failure,
        identityNotAllowed: identityNotAllowed,
      );

      final policy = DeliveryPolicy.forEvent(
        eventOfKind(Nip01Event.kTextNoteKind),
      );
      final identityNotAllowed = failed(
        'identityNotAllowed: auth-required: please authenticate',
        identityNotAllowed: true,
      );

      expect(
        policy.resolveNextState(
          identityNotAllowed,
          auth: const AuthPolicy.never(),
        ),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.resolveNextState(identityNotAllowed),
        RelayDeliveryState.authRequired,
      );
      expect(
        policy.resolveNextState(failed('vetoed: invalid signature')),
        RelayDeliveryState.transientFailure,
      );
      expect(
        policy.resolveNextState(failed('unreachable')),
        RelayDeliveryState.transientFailure,
      );
      expect(
        DeliveryPolicy.forEvent(
          eventOfKind(20001),
        ).resolveNextState(failed('unreachable')),
        RelayDeliveryState.permanentFailure,
      );
    });

    test('classifies auth-required separately from permanent failures', () {
      final event = Nip01Event(
        id: 'event-1',
        pubKey: 'pubkey',
        createdAt: 1700000002,
        kind: Nip01Event.kTextNoteKind,
        tags: const [],
        content: 'text',
        sig: 'sig',
      );

      final policy = DeliveryPolicy.forEvent(event);

      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'auth-required: please authenticate',
          ),
        ),
        RelayDeliveryState.authRequired,
      );
      // Uppercase / leading whitespace must still be classified as auth-required.
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: '  AUTH-REQUIRED: please authenticate',
          ),
        ),
        RelayDeliveryState.authRequired,
      );
      expect(policy.shouldRetryState(RelayDeliveryState.authRequired), isTrue);
      expect(
        policy.retryDelayFor(
          state: RelayDeliveryState.authRequired,
          attemptCount: 1,
        ),
        const Duration(minutes: 1),
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'invalid signature',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.shouldRetryState(RelayDeliveryState.permanentFailure),
        isFalse,
      );
      expect(
        policy.retryDelayFor(
          state: RelayDeliveryState.permanentFailure,
          attemptCount: 1,
        ),
        Duration.zero,
      );
    });

    test('treats a duplicate response as acked', () {
      final event = Nip01Event(
        id: 'event-dup',
        pubKey: 'pubkey',
        createdAt: 1700000002,
        kind: Nip01Event.kTextNoteKind,
        tags: const [],
        content: 'text',
        sig: 'sig',
      );

      final policy = DeliveryPolicy.forEvent(event);

      // A relay answering `duplicate:` already holds the event, so even with
      // OK=false the delivery to that relay is effectively done.
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'duplicate: already have this event',
          ),
        ),
        RelayDeliveryState.acked,
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'DUPLICATE: already have this event',
          ),
        ),
        RelayDeliveryState.acked,
      );
    });

    test('treats policy violations as permanent failures', () {
      final event = Nip01Event(
        id: 'event-2',
        pubKey: 'pubkey',
        createdAt: 1700000002,
        kind: Nip01Event.kTextNoteKind,
        tags: const [],
        content: 'text',
        sig: 'sig',
      );

      final policy = DeliveryPolicy.forEvent(event);

      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'policy violation: forbidden kind',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'kind 1059 is not allowed on this relay',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'restricted: not allowed to write',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'invalid: event creation date is too far off',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: "kind 1111: 'A' tag must reference a kind 32267",
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
    });

    test('keeps rate-limited and error prefixes retryable', () {
      final event = Nip01Event(
        id: 'event-3',
        pubKey: 'pubkey',
        createdAt: 1700000003,
        kind: Nip01Event.kTextNoteKind,
        tags: const [],
        content: 'text',
        sig: 'sig',
      );

      final policy = DeliveryPolicy.forEvent(event);

      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'rate-limited: slow down',
          ),
        ),
        RelayDeliveryState.transientFailure,
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'error: backend unavailable',
          ),
        ),
        RelayDeliveryState.transientFailure,
      );
    });

    test('treats common raw strfry validation failures as permanent', () {
      final event = Nip01Event(
        id: 'event-4',
        pubKey: 'pubkey',
        createdAt: 1700000004,
        kind: Nip01Event.kTextNoteKind,
        tags: const [],
        content: 'text',
        sig: 'sig',
      );

      final policy = DeliveryPolicy.forEvent(event);

      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'bad signature',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'too many tags: 1200',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
      expect(
        policy.resolveNextState(
          DeliveryResponse(
            relayUrl: 'wss://relay.example',
            message: 'event too large: 999999',
          ),
        ),
        RelayDeliveryState.permanentFailure,
      );
    });

    test('uses faster backoff for deletion events', () {
      final deletionEvent = Nip01Event(
        id: 'delete-1',
        pubKey: 'pubkey',
        createdAt: 1700000003,
        kind: 5,
        tags: const [
          ['e', 'target'],
        ],
        content: 'delete',
        sig: 'sig',
      );
      final noteEvent = Nip01Event(
        id: 'note-1',
        pubKey: 'pubkey',
        createdAt: 1700000004,
        kind: Nip01Event.kTextNoteKind,
        tags: const [],
        content: 'note',
        sig: 'sig',
      );

      final deletionPolicy = DeliveryPolicy.forEvent(deletionEvent);
      final notePolicy = DeliveryPolicy.forEvent(noteEvent);

      expect(
        deletionPolicy.retryDelayFor(
          state: RelayDeliveryState.transientFailure,
          attemptCount: 1,
        ),
        lessThan(
          notePolicy.retryDelayFor(
            state: RelayDeliveryState.transientFailure,
            attemptCount: 1,
          ),
        ),
      );
    });
  });
}
