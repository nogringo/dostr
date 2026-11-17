import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/src/domain_layer/usecases/relay_manager/request_state.dart';
import 'package:test/test.dart';

final _filters = [
  Filter(kinds: [Nip01Event.kTextNoteKind]),
];

RequestState _query() => RequestState(
  'a-query',
  closeOnEose: true,
  timeoutDuration: const Duration(seconds: 5),
);

void main() {
  group('RequestState.didAllRequestsFinish', () {
    test('a request that reached no relay is finished', () {
      expect(_query().didAllRequestsFinish, isTrue);
    });

    test('waits for every relay it was sent to', () {
      final state = _query();
      final fast = RelayConnectionKey.anonymous(
        RelayUrl.parse('wss://fast.example.com'),
      );
      final slow = RelayConnectionKey.anonymous(
        RelayUrl.parse('wss://slow.example.com'),
      );
      state.addRequest(fast, _filters);
      state.addRequest(slow, _filters);

      state.requests[fast]!.markCaughtUp();
      expect(state.didAllRequestsFinish, isFalse);

      state.requests[slow]!.markCaughtUp();
      expect(state.didAllRequestsFinish, isTrue);
    });

    test('waits for a relay whose connection is still being worked out', () {
      final state = _query();
      final fast = RelayConnectionKey.anonymous(
        RelayUrl.parse('wss://fast.example.com'),
      );

      // a second send path is resolving which connection to use, so it has no
      // entry yet. The relay that answered must not look like the only one
      state.pendingConnections++;
      state.addRequest(fast, _filters);
      state.requests[fast]!.markCaughtUp();

      expect(state.didAllRequestsFinish, isFalse);

      state.pendingConnections--;
      expect(state.didAllRequestsFinish, isTrue);
    });

    test('a relay that is authenticating is not finished', () {
      final state = _query();
      final key = RelayConnectionKey.anonymous(
        RelayUrl.parse('wss://relay.example.com'),
      );
      state.addRequest(key, _filters);

      state.requests[key]!.markClosed(null);
      state.requests[key]!.markRetryingAuth();
      expect(state.didAllRequestsFinish, isFalse);

      state.requests[key]!.endAuthRetry();
      expect(state.didAllRequestsFinish, isTrue);
    });
  });

  group('RequestState timeout pauses', () {
    RequestState withTimeout(Duration timeout) =>
        RequestState('a-query', closeOnEose: true, timeoutDuration: timeout);

    test('the timer waits for every pause to resume', () async {
      final state = withTimeout(const Duration(milliseconds: 300));
      state.pauseTimeout();
      state.pauseTimeout();

      state.resumeTimeout();
      await Future.delayed(const Duration(milliseconds: 500));
      expect(state.timedOut, isFalse);

      state.resumeTimeout();
      await Future.delayed(const Duration(milliseconds: 500));
      expect(state.timedOut, isTrue);
    });

    test('a second pause keeps what the first one left', () async {
      final state = withTimeout(const Duration(milliseconds: 600));
      await Future.delayed(const Duration(milliseconds: 400));
      state.pauseTimeout();
      state.resumeTimeout();
      await Future.delayed(const Duration(milliseconds: 100));
      state.pauseTimeout();
      await Future.delayed(const Duration(milliseconds: 700));
      expect(state.timedOut, isFalse);

      state.resumeTimeout();
      await Future.delayed(const Duration(milliseconds: 250));
      expect(state.timedOut, isTrue);
    });
  });
}
