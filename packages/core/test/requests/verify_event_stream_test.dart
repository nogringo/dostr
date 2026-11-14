import 'dart:async';

import 'package:dostr_core/src/domain_layer/usecases/requests/verify_event_stream.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

/// Holds each verification until [release] is called with its event's content.
class _GatedVerifier implements EventVerifier {
  final _gates = <String, Completer<bool>>{};

  Completer<bool> _gate(String content) => _gates[content] ??= Completer();

  void release(String content) => _gate(content).complete(true);

  @override
  Future<bool> verify(Nip01Event event) => _gate(event.content).future;
}

void main() {
  List<Nip01Event> notes(int count) => [
    for (var i = 0; i < count; i++) signedEvent(content: 'note $i'),
  ];

  List<String> ids(Iterable<Nip01Event> events) => [
    for (final event in events) event.id,
  ];

  for (final (count, maxConcurrent) in [
    (3, 100),
    (6, 2),
    (5, 3),
    (5, 10),
    (100, 50),
  ]) {
    test('yields $count valid events in order, '
        'at most $maxConcurrent verified at a time', () async {
      final events = notes(count);

      final results = await VerifyEventStream(
        unverifiedStreamInput: Stream.fromIterable(events),
        eventVerifier: FakeVerifier(),
        maxConcurrent: maxConcurrent,
      )().toList();

      expect(ids(results), ids(events));
    });
  }

  test('drops the events whose signature does not hold', () async {
    final valid = notes(2);
    final forged = signedEvent(content: 'forged').copyWith(sig: 'e' * 128);

    final results = await VerifyEventStream(
      unverifiedStreamInput: Stream.fromIterable([valid[0], forged, valid[1]]),
      eventVerifier: FakeVerifier(),
    )().toList();

    expect(ids(results), ids(valid));
  });

  test('an empty input yields nothing', () async {
    final results = await VerifyEventStream(
      unverifiedStreamInput: const Stream.empty(),
      eventVerifier: FakeVerifier(),
    )().toList();

    expect(results, isEmpty);
  });

  test('is a broadcast stream every listener gets in full', () async {
    final events = notes(2);
    final stream = VerifyEventStream(
      unverifiedStreamInput: Stream.fromIterable(events),
      eventVerifier: FakeVerifier(),
    )();

    expect(stream.isBroadcast, isTrue);
    final results = await Future.wait([stream.toList(), stream.toList()]);
    expect(results.map(ids), [ids(events), ids(events)]);
  });

  for (final maxConcurrent in [2, 10]) {
    test('yields each event once verified, before the input ends, '
        'at most $maxConcurrent verified at a time', () async {
      final input = StreamController<Nip01Event>();
      final received = <Nip01Event>[];
      final subscription = VerifyEventStream(
        unverifiedStreamInput: input.stream,
        eventVerifier: FakeVerifier(),
        maxConcurrent: maxConcurrent,
      )().listen(received.add);
      addTearDown(input.close);
      addTearDown(subscription.cancel);
      final events = notes(6);

      for (final event in events.take(2)) {
        input.add(event);
        await eventually(() => received.length == events.indexOf(event) + 1);
      }
      events.skip(2).forEach(input.add);

      await eventually(() => received.length == events.length);
      expect(ids(received), ids(events));
    });
  }

  test('yields in the order verifications end, not the input order', () async {
    final verifier = _GatedVerifier();
    final received = <Nip01Event>[];
    final subscription = VerifyEventStream(
      unverifiedStreamInput: Stream.fromIterable([
        signedEvent(content: 'slow'),
        signedEvent(content: 'fast'),
      ]),
      eventVerifier: verifier,
    )().listen(received.add);
    addTearDown(subscription.cancel);

    verifier.release('fast');
    await eventually(() => received.isNotEmpty);
    expect(received.single.content, 'fast');

    verifier.release('slow');
    await eventually(() => received.length == 2);
    expect(received.last.content, 'slow');
  });
}
