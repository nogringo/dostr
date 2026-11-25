import 'dart:async';

import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

class FakeRelayLists {
  final Map<String, UrlListLookup> answers = {};
  final List<String> calls = [];
  Completer<void>? gate;

  void set(String pubkey, UrlListKind kind, UrlListLookup answer) =>
      answers['${kind.name}|$pubkey'] = answer;

  UrlListFn get fn => (pubkey, kind) async {
    final id = '${kind.name}|$pubkey';
    calls.add(id);
    await gate?.future;
    return answers[id] ?? const UrlListLookup.unavailable('offline');
  };
}

void main() {
  group('PublishQueue with a relay set', () {
    late MemoryPublishQueueStore store;

    setUp(() {
      store = MemoryPublishQueueStore();
    });

    PublishQueue queueFor(FakePublisher fake, FakeRelayLists? lists) =>
        PublishQueue(
          publishFn: fake.fn,
          relayListFn: lists?.fn,
          store: store,
          initialBackoff: const Duration(milliseconds: 5),
          maxBackoff: const Duration(milliseconds: 5),
        );

    test('persists unresolved without waiting for the lookup', () async {
      final fake = FakePublisher()..ack('wss://w');
      final lists = FakeRelayLists()
        ..gate = Completer<void>()
        ..set('p', UrlListKind.outbox, const UrlListLookup.found(['wss://w/']));
      final queue = queueFor(fake, lists);

      final event = makeEvent();
      final record = await queue.publish(
        event,
        relaySet: const UrlSet.outbox('p'),
      );
      expect(record.status, QueuedPublishStatus.pending);
      expect(record.relays, isEmpty);
      expect(record.pendingRelaySet, isA<OutboxUrls>());
      expect(fake.calls, isEmpty);

      lists.gate!.complete();
      final delivered = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
      expect(delivered.relays, ['wss://w']);
      expect(delivered.pendingRelaySet, isNull);

      await queue.dispose();
    });

    test('an unavailable lookup backs off and is retried', () async {
      final fake = FakePublisher()..ack('wss://w');
      final lists = FakeRelayLists();
      final queue = queueFor(fake, lists);

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.outbox('p'));
      final waiting = await waitFor(
        queue,
        event.id,
        (r) => r.resolutionAttempts == 1,
      );
      expect(waiting.status, QueuedPublishStatus.pending);
      expect(waiting.resolutionError, contains('offline'));
      expect(fake.calls, isEmpty);

      lists.set(
        'p',
        UrlListKind.outbox,
        const UrlListLookup.found(['wss://w']),
      );
      await Future.delayed(const Duration(milliseconds: 20));
      await queue.retryNow();
      final delivered = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );
      expect(delivered.resolutionAttempts, 0);
      expect(delivered.resolutionError, isNull);

      await queue.dispose();
    });

    test('freezes relays at the first successful resolution', () async {
      final fake = FakePublisher()..fail('wss://w');
      final lists = FakeRelayLists()
        ..set('p', UrlListKind.outbox, const UrlListLookup.found(['wss://w']));
      final queue = queueFor(fake, lists);

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.outbox('p'));
      await waitFor(queue, event.id, (r) => r.attempts >= 1);

      lists.set(
        'p',
        UrlListKind.outbox,
        const UrlListLookup.found(['wss://x']),
      );
      await Future.delayed(const Duration(milliseconds: 20));
      await queue.retryNow();
      final retried = await waitFor(queue, event.id, (r) => r.attempts >= 2);
      expect(retried.relays, ['wss://w']);
      expect(lists.calls, ['outbox|p']);

      await queue.dispose();
    });

    test('a set resolving to no relay fails the entry', () async {
      final fake = FakePublisher();
      final lists = FakeRelayLists()
        ..set('p', UrlListKind.outbox, const UrlListLookup.notFound());
      final queue = queueFor(fake, lists);

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.outbox('p'));
      final failed = await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.failed,
      );
      expect(failed.resolutionError, 'relay set resolved to no relay');
      expect(fake.calls, isEmpty);

      await queue.dispose();
    });

    test('a new set on a delivered entry resolves and reopens it', () async {
      final fake = FakePublisher()..ackAll(['wss://a', 'wss://b']);
      final lists = FakeRelayLists()
        ..set('p', UrlListKind.inbox, const UrlListLookup.found(['wss://b']));
      final queue = queueFor(fake, lists);

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.explicit(['wss://a']));
      await waitFor(
        queue,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );

      await queue.publish(event, relaySet: const UrlSet.inbox('p'));
      final delivered = await waitFor(
        queue,
        event.id,
        (r) =>
            r.status == QueuedPublishStatus.delivered &&
            r.ackedRelays.contains('wss://b'),
      );
      expect(delivered.relays, ['wss://a', 'wss://b']);

      await queue.dispose();
    });

    test('an unresolved set survives a restart', () async {
      final fake = FakePublisher()..ack('wss://w');
      final first = queueFor(fake, FakeRelayLists());
      final event = makeEvent();
      await first.publish(event, relaySet: const UrlSet.dm('p'));
      await waitFor(first, event.id, (r) => r.resolutionAttempts >= 1);
      await first.dispose();

      final lists = FakeRelayLists()
        ..set('p', UrlListKind.outbox, const UrlListLookup.notFound())
        ..set('p', UrlListKind.dm, const UrlListLookup.found(['wss://w']));
      final second = queueFor(fake, lists);
      await Future.delayed(const Duration(milliseconds: 20));
      await second.retryNow();
      await waitFor(
        second,
        event.id,
        (r) => r.status == QueuedPublishStatus.delivered,
      );

      await second.dispose();
    });

    test('dispose abandons a resolution waiting on a lookup', () async {
      final fake = FakePublisher();
      final lists = FakeRelayLists()..gate = Completer<void>();
      final queue = queueFor(fake, lists);

      final event = makeEvent();
      await queue.publish(event, relaySet: const UrlSet.private('p'));
      while (lists.calls.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
      await queue.dispose().timeout(const Duration(seconds: 1));

      final record = (await store.readAll()).single;
      expect(record.pendingRelaySet, isA<PrivateUrls>());
      expect(record.resolutionAttempts, 0);
      lists.gate!.complete();
    });

    test('an explicit-only set resolves at enqueue time', () async {
      final fake = FakePublisher()..ack('wss://b');
      final queue = queueFor(fake, null);

      final record = await queue.publish(
        makeEvent(),
        relaySet: const UrlSet.fallback([
          UrlSet.explicit([]),
          UrlSet.explicit(['wss://b']),
        ]),
      );
      expect(record.relays, ['wss://b']);
      expect(record.pendingRelaySet, isNull);

      await queue.dispose();
    });

    test('rejects invalid arguments', () async {
      final queue = queueFor(FakePublisher(), null);
      final event = makeEvent();
      expect(
        () => queue.publish(event, relaySet: const UrlSet.outbox('p')),
        throwsStateError,
      );
      for (final invalid in const [
        UrlSet.explicit([]),
        UrlSet.explicit(['', ' ']),
        UrlSet.fallback([UrlSet.explicit([]), UrlSet.union([])]),
        UrlSet.blossom('p'),
        UrlSet.union([
          UrlSet.explicit(['wss://a']),
          UrlSet.blossom('p'),
        ]),
      ]) {
        await expectLater(
          queue.publish(event, relaySet: invalid),
          throwsArgumentError,
        );
      }
      expect(await queue.listAll(), isEmpty);
      await queue.dispose();
    });
  });
}
