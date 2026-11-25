import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import 'package:test/test.dart';

import 'support/fake_publisher.dart';
import 'support/helpers.dart';

const _relays = UrlSet.explicit(['wss://a']);

class _FlakyStore extends MemoryPublishQueueStore {
  bool refuseReads = false;
  bool refuseWrites = false;
  Duration writeDelay = Duration.zero;

  @override
  Future<List<QueuedPublish>> readAll() async {
    if (refuseReads) throw StateError('read refused');
    return super.readAll();
  }

  @override
  Future<void> put(List<QueuedPublish> records) async {
    if (refuseWrites) throw StateError('write refused');
    await Future<void>.delayed(writeDelay);
    return super.put(records);
  }
}

void main() {
  late _FlakyStore store;
  late FakePublisher fake;

  setUp(() {
    store = _FlakyStore();
    fake = FakePublisher()..ack('wss://a');
  });

  PublishQueue newQueue() => PublishQueue(publishFn: fake.fn, store: store);

  test('a write the store refuses changes nothing', () async {
    final queue = newQueue();
    final event = makeEvent();

    store.refuseWrites = true;
    await expectLater(
      queue.publish(event, relaySet: _relays),
      throwsA(isA<StateError>()),
    );
    expect(await queue.get(event.id), isNull);

    store.refuseWrites = false;
    await queue.publish(event, relaySet: _relays);
    await waitFor(
      queue,
      event.id,
      (r) => r.status == QueuedPublishStatus.delivered,
    );

    await queue.dispose();
  });

  test('a read the store refuses is tried again on the next call', () async {
    final event = makeEvent();
    await newQueue().publish(event, relaySet: _relays);

    final queue = newQueue();
    store.refuseReads = true;
    await expectLater(queue.get(event.id), throwsA(isA<StateError>()));
    store.refuseReads = false;
    expect(await queue.get(event.id), isNotNull);

    await queue.dispose();
  });

  test('watch emits the record, then each write of it', () async {
    final queue = newQueue();
    final event = makeEvent();

    final statuses = expectLater(
      queue.watch(event.id).map((r) => r?.status),
      emitsInOrder([
        null,
        QueuedPublishStatus.pending,
        QueuedPublishStatus.delivered,
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    await queue.publish(event, relaySet: _relays);
    await statuses;

    await queue.dispose();
  });

  test('watchPending drops a record once delivered', () async {
    final queue = newQueue();
    final event = makeEvent();

    final pending = expectLater(
      queue.watchPending().map((records) => [for (final r in records) r.id]),
      emitsInOrder([
        isEmpty,
        [event.id],
        isEmpty,
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    await queue.publish(event, relaySet: _relays);
    await pending;

    await queue.dispose();
  });

  test('dispose waits for the writes the caller did not await', () async {
    fake.gate = Completer<Map<RelayUrl, RelayPublishOutcome>>();
    final queue = newQueue();
    final event = makeEvent();
    await queue.publish(event, relaySet: _relays);

    store.writeDelay = const Duration(milliseconds: 20);
    unawaited(queue.cancel(event.id));
    await queue.dispose();
    expect(
      (await store.readAll()).single.status,
      QueuedPublishStatus.cancelled,
    );
  });
}
