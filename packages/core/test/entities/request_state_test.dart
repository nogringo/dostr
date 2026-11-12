import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/src/request_state.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  const url = 'wss://relay.example';
  final anonymous = RelayConnectionKey.anonymous(url);
  final bound = RelayConnectionKey.authenticated(url, alice);
  final notes = [
    Filter(kinds: [1]),
  ];

  late RequestState state;

  RequestState listened(RequestState state) {
    state.networkController.stream.listen((_) {});
    return state;
  }

  setUp(() => state = listened(RequestState.query('query')));

  tearDown(() => state.close());

  RelayRequestStatus? statusOf(String url) => state.relayOutcomes[url]?.status;

  test('collapses the connections to one relay into its outcome', () {
    state.addRequest(anonymous, notes);
    state.requests[anonymous]!.markClosed('auth-required: x');
    expect(statusOf(url), RelayRequestStatus.closed);

    state.addRequest(bound, notes);
    expect(statusOf(url), RelayRequestStatus.pending);

    state.requests[bound]!.receivedEOSE = true;
    expect(statusOf(url), RelayRequestStatus.eose);
  });

  test('keeps the reason of a CLOSED and of a notSent', () {
    state.addRequest(anonymous, notes);
    state.requests[anonymous]!.markClosed('blocked: no');
    expect(
      state.relayOutcomes[url],
      const RelayRequestOutcome(
        RelayRequestStatus.closed,
        message: 'blocked: no',
      ),
    );

    state.requests[anonymous]!.forgetAnswers();
    state.requests[anonymous]!.markNotSent(
      const RelayFailure(RelayFailureKind.blocked),
    );
    expect(
      state.relayOutcomes[url],
      const RelayRequestOutcome(
        RelayRequestStatus.notSent,
        failure: RelayFailure(RelayFailureKind.blocked),
      ),
    );
  });

  test('an authentication in progress counts as pending', () {
    state.addRequest(bound, notes);
    state.requests[bound]!
      ..markClosed('auth-required: x')
      ..retryingAuth = true;

    expect(statusOf(url), RelayRequestStatus.pending);
    expect(state.didAllRequestsFinish, isFalse);
  });

  test('outcomesStream replays what it holds to a late listener', () async {
    state.addRequest(anonymous, notes);
    state.requests[anonymous]!.receivedEOSE = true;

    final first = await state.relayOutcomesStream.first;

    expect(first[url]!.status, RelayRequestStatus.eose);
  });

  test('a paused timeout keeps the time it had left', () async {
    final timed = listened(
      RequestState.query('timed', timeout: const Duration(milliseconds: 200)),
    );
    addTearDown(timed.close);
    final timedOut = Completer<void>();
    timed.onTimeout = (_) => timedOut.complete();

    timed.pauseTimeout();
    timed.pauseTimeout();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    timed.resumeTimeout();
    expect(timedOut.isCompleted, isFalse);

    timed.resumeTimeout();
    await timedOut.future.timeout(const Duration(seconds: 1));
    expect(timed.timedOut, isTrue);
  });
}
