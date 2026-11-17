import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/publish_state.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  final first = RelayUrl.parse('wss://first.example');
  final second = RelayUrl.parse('wss://second.example');

  PublishState publish({Duration timeout = const Duration(minutes: 1)}) =>
      PublishState(signedEvent(), relays: [first, second], timeout: timeout);

  test('an answer shows in the outcomes as soon as it lands', () {
    final state = publish();

    state.end(first, const RelayPublishOutcome.accepted());

    expect(state.outcomes, {
      first: const RelayPublishOutcome.accepted(),
      second: const RelayPublishOutcome.pending(),
    });
    expect(state.isOver, isFalse);
  });

  test('the first answer of a relay stands', () async {
    final state = publish();

    state.end(first, const RelayPublishOutcome.accepted('saved'));
    state.end(
      first,
      const RelayPublishOutcome.failed(
        RelayFailure(RelayFailureKind.connectionLost),
      ),
    );
    state.end(second, const RelayPublishOutcome.refused('blocked: spam'));

    expect(await state.done, {
      first: const RelayPublishOutcome.accepted('saved'),
      second: const RelayPublishOutcome.refused('blocked: spam'),
    });
  });

  test('times out the relays that did not answer', () async {
    final state = publish(timeout: const Duration(milliseconds: 50));

    state.end(first, const RelayPublishOutcome.accepted());

    expect(await state.done, {
      first: const RelayPublishOutcome.accepted(),
      second: const RelayPublishOutcome.timedOut(),
    });
  });

  test('a publish without relays is over right away', () async {
    final state = PublishState(
      signedEvent(),
      relays: [],
      timeout: const Duration(minutes: 1),
    );

    expect(state.isOver, isTrue);
    expect(await state.done, isEmpty);
  });
}
