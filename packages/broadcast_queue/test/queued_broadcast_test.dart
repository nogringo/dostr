import 'package:dostr_broadcast_queue/dostr_broadcast_queue.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

RelayUrl _relay(String url) => RelayUrl.parse(url);

QueuedBroadcast _record({
  Nip01Event? event,
  String? account,
  List<String> relays = const ['wss://relay.example'],
  List<String> ackedRelays = const [],
  Map<String, String> lastErrors = const {},
  Map<String, String> terminalErrors = const {},
  Map<String, int> inaccessibleAttempts = const {},
  int attempts = 0,
  int onlineFailures = 0,
  int? failedAt,
}) {
  event ??= makeEvent();
  return QueuedBroadcast(
    id: event.id,
    account: account,
    event: event,
    relays: relays.map(_relay).toList(),
    ackedRelays: ackedRelays.map(_relay).toList(),
    lastErrors: lastErrors.map((k, v) => MapEntry(_relay(k), v)),
    terminalErrors: terminalErrors.map((k, v) => MapEntry(_relay(k), v)),
    inaccessibleAttempts: inaccessibleAttempts.map(
      (k, v) => MapEntry(_relay(k), v),
    ),
    attempts: attempts,
    onlineFailures: onlineFailures,
    firstAttemptAt: null,
    lastAttemptAt: null,
    nextAttemptAt: 0,
    deliveredAt: null,
    failedAt: failedAt,
    createdAt: 0,
  );
}

void main() {
  group('QueuedBroadcast', () {
    test('remainingRelays excludes acked and terminal relays', () {
      final r = _record(
        relays: const ['wss://a', 'wss://b', 'wss://c'],
        ackedRelays: const ['wss://b'],
        terminalErrors: const {'wss://c': 'pow: too low'},
      );
      expect(r.remainingRelays, ['wss://a']);
    });

    test('status reflects terminal timestamps', () {
      final base = _record(
        relays: const ['wss://a'],
        ackedRelays: const ['wss://a'],
        attempts: 1,
      );
      expect(base.status, BroadcastStatus.pending);
      expect(base.copyWith(failedAt: 1).status, BroadcastStatus.failed);
      expect(base.copyWith(deliveredAt: 1).status, BroadcastStatus.delivered);
      expect(
        base.copyWith(deliveredAt: 1, supersededBy: 'newer').status,
        BroadcastStatus.superseded,
      );
      final restored = QueuedBroadcast.fromMap(
        base.copyWith(supersededBy: 'newer').toMap(),
      );
      expect(restored.supersededBy, 'newer');
      expect(
        base.copyWith(deliveredAt: 1, cancelledAt: 1).status,
        BroadcastStatus.cancelled,
      );
      expect(
        QueuedBroadcast.fromMap(
          base.copyWith(cancelledAt: 1).toMap(),
        ).cancelledAt,
        1,
      );
    });

    test('keyFor composes account and event id, bare when unattributed', () {
      expect(QueuedBroadcast.keyFor(eventId: 'evt'), 'evt');
      expect(QueuedBroadcast.keyFor(eventId: 'evt', account: null), 'evt');
      expect(
        QueuedBroadcast.keyFor(eventId: 'evt', account: 'npub'),
        'npub|evt',
      );
    });

    test('toMap → fromMap roundtrip preserves the account', () {
      final original = _record(account: 'account-pubkey');
      final restored = QueuedBroadcast.fromMap(original.toMap());
      expect(restored.account, 'account-pubkey');
      expect(restored.key, 'account-pubkey|${original.id}');
    });

    test('toMap → fromMap roundtrip preserves the delivery state', () {
      final original = _record(
        relays: const ['wss://relay.example'],
        lastErrors: const {'wss://relay.example': 'timed out'},
        terminalErrors: const {'wss://other.example': 'blocked: banned'},
        inaccessibleAttempts: const {'wss://relay.example': 2},
        attempts: 2,
        onlineFailures: 1,
        failedAt: 400,
      );
      final restored = QueuedBroadcast.fromMap(original.toMap());
      expect(restored.id, original.id);
      expect(restored.event.id, original.event.id);
      expect(restored.event.sig, original.event.sig);
      expect(restored.relays, original.relays);
      expect(restored.lastErrors, original.lastErrors);
      expect(restored.terminalErrors, original.terminalErrors);
      expect(restored.inaccessibleAttempts, original.inaccessibleAttempts);
      expect(restored.attempts, original.attempts);
      expect(restored.onlineFailures, original.onlineFailures);
      expect(restored.failedAt, original.failedAt);
    });

    test('fromMap reads a record of broadcast_queue_shim_for_ndk', () {
      final event = makeEvent();
      final restored = QueuedBroadcast.fromMap({
        'id': event.id,
        'event': event.toJson(),
        'relays': const ['wss://relay.example', 'not a relay'],
        'ackedRelays': const [],
        'lastErrors': const {'not a relay': 'no response'},
        'attempts': 0,
        'firstAttemptAt': null,
        'lastAttemptAt': null,
        'nextAttemptAt': 0,
        'deliveredAt': null,
        'createdAt': 0,
        'forcedRelays': null,
      });
      expect(restored.account, isNull);
      expect(restored.key, event.id);
      expect(restored.relays, ['wss://relay.example']);
      expect(restored.lastErrors, isEmpty);
      expect(restored.terminalErrors, isEmpty);
      expect(restored.inaccessibleAttempts, isEmpty);
      expect(restored.onlineFailures, 0);
      expect(restored.failedAt, isNull);
    });
  });
}
