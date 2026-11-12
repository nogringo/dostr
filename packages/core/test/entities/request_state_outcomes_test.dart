import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/src/request_state.dart';
import 'package:test/test.dart';

/// What no relay can be made to do on demand: a connection that goes away, and
/// two connections to one relay ending differently.
void main() {
  group('relay outcomes collapse', () {
    const url = "wss://relay.example.com";
    final filter = Filter(kinds: [Nip01Event.kTextNoteKind]);

    RequestState buildState() => RequestState.subscription("outcome-test");

    test('a connection that went away reports disconnected', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.requests[key]!.connectionGone = true;

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.disconnected),
      });
    });

    test('an eose on one connection wins over a closed on another', () {
      final state = buildState();
      final anonymous = RelayConnectionKey.anonymous(url);
      final authenticated = RelayConnectionKey.authenticated(url, "a" * 64);
      state.addRequest(anonymous, [filter]);
      state.addRequest(authenticated, [filter]);
      state.requests[anonymous]!
        ..receivedClosed = true
        ..closedMessage = "auth-required: we only serve authenticated users";
      state.requests[authenticated]!.receivedEOSE = true;

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });

    test('a request that could not be sent reports notSent and why', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.requests[key]!.markNotSent(
        const RelayFailure(RelayFailureKind.unreachable),
      );

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(
          RelayRequestStatus.notSent,
          failure: RelayFailure(RelayFailureKind.unreachable),
        ),
      });
      expect(state.didAllRequestsFinish, isTrue);
    });

    test('a request sent after all is no longer notSent', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.requests[key]!.markNotSent(
        const RelayFailure(RelayFailureKind.unreachable),
      );

      state.requests[key]!.forgetAnswers();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test('a connection sent again after it went away is pending once more', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.requests[key]!.connectionGone = true;

      // what a subscription replayed on a replacement socket goes through
      state.requests[key]!.forgetAnswers();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test('the stream reports a change once and a repeat not at all', () async {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);

      final seen = <Map<String, RelayRequestOutcome>>[];
      final subscription = state.relayOutcomesStream.listen(seen.add);
      await Future.delayed(Duration.zero);

      state.requests[key]!.receivedEOSE = true;
      state.requests[key]!.receivedEOSE = true;
      await Future.delayed(Duration.zero);
      await subscription.cancel();

      expect(seen, [
        {url: RelayRequestOutcome(RelayRequestStatus.pending)},
        {url: RelayRequestOutcome(RelayRequestStatus.eose)},
      ]);
    });

    test('a late listener gets the outcomes it was not there for', () async {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.requests[key]!.receivedEOSE = true;

      expect(await state.relayOutcomesStream.first, {
        url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });

    test('a connection retrying its authentication stays pending', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.requests[key]!
        ..receivedClosed = true
        ..retryingAuth = true;

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });
  });

  group('a subscription after its EOSE', () {
    const url = "wss://relay.example.com";
    final filter = Filter(kinds: [Nip01Event.kTextNoteKind]);
    final key = RelayConnectionKey.anonymous(url);

    RequestState caughtUp() {
      final state = RequestState.subscription("caught-up")
        ..addRequest(key, [filter]);
      state.requests[key]!.receivedEOSE = true;
      return state;
    }

    test('reports eose and is not over', () {
      final state = caughtUp();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
      expect(state.endedOn(state.requests[key]!), isFalse);
      expect(state.didAllRequestsFinish, isFalse);
    });

    test('reports the CLOSED that ends it on the relay', () {
      final state = caughtUp();
      state.requests[key]!.markClosed("error: shutting down");

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(
          RelayRequestStatus.closed,
          message: "error: shutting down",
        ),
      });
      expect(state.didAllRequestsFinish, isTrue);
    });

    test('reports a connection that went away', () {
      final state = caughtUp();
      state.requests[key]!.connectionGone = true;

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.disconnected),
      });
    });

    test('is pending again once sent again', () {
      final state = caughtUp();
      state.requests[key]!.forgetAnswers();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test('a query keeps its eose over a later timeout', () {
      final state = RequestState.query("query")..addRequest(key, [filter]);
      state.requests[key]!.receivedEOSE = true;
      state.timedOut = true;

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
      expect(state.didAllRequestsFinish, isTrue);
    });
  });
}
