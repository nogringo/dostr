import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/src/reqs/request_state.dart';
import 'package:test/test.dart';

/// What no relay can be made to do on demand: a connection that goes away, and
/// two connections to one relay ending differently.
void main() {
  group('relay outcomes', () {
    final url = RelayUrl.parse("wss://relay.example.com");
    final filter = Filter(kinds: [Nip01Event.kTextNoteKind]);

    RequestState buildState() =>
        RequestState("outcome-test", closeOnEose: false);

    test('a connection that went away reports disconnected', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter])
        ..markOnItsWay()
        ..markGone();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.disconnected),
      });
    });

    group('handed over to a bound connection', () {
      final bound = RelayConnectionKey.authenticated(url, "a" * 64);

      RequestState handedOver() {
        final state = buildState();
        state
            .addRequest(RelayConnectionKey.anonymous(url), [filter])
            .markClosed("auth-required: we only serve authenticated users");
        state.addRequest(bound, [filter]).markOnItsWay();
        return state;
      }

      test('reports the eose of the bound connection', () {
        final state = handedOver();
        state.requests[bound]!.markCaughtUp();

        expect(state.relayOutcomes, {
          url: RelayRequestOutcome(RelayRequestStatus.eose),
        });
      });

      test('reports timedOut, not the anonymous refusal', () {
        final state = handedOver()..timedOut = true;

        expect(state.relayOutcomes, {
          url: RelayRequestOutcome(RelayRequestStatus.timedOut),
        });
      });

      test('reports cancelled, not the anonymous refusal', () {
        final state = handedOver()..cancel();

        expect(state.relayOutcomes, {
          url: RelayRequestOutcome(RelayRequestStatus.cancelled),
        });
      });

      test('reports disconnected, not the anonymous refusal', () {
        final state = handedOver();
        state.requests[bound]!.markGone();

        expect(state.relayOutcomes, {
          url: RelayRequestOutcome(RelayRequestStatus.disconnected),
        });
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

      state.requests[key]!.markOnItsWay();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test('a connection still opening is not given up as gone', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]).markGone();

      expect(state.requests[key]!.progress, RelayReqProgress.connecting);
      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test('a connection sent again after it went away is pending once more', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter])
        ..markOnItsWay()
        ..markGone();

      // what a subscription replayed on a replacement socket goes through
      state.requests[key]!.markOnItsWay();

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

      state.requests[key]!.markCaughtUp();
      state.requests[key]!.markCaughtUp();
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
      state.requests[key]!.markCaughtUp();

      expect(await state.relayOutcomesStream.first, {
        url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
    });

    test('a connection retrying its authentication stays pending', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.requests[key]!.markRetryingAuth('auth-required: x');

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test('a timeout ends a relay retrying its authentication', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.requests[key]!.markRetryingAuth('auth-required: x');
      state.timedOut = true;

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.timedOut),
      });
    });

    test('a request closed on its timeout is not cancelled', () {
      final state = buildState();
      final key = RelayConnectionKey.anonymous(url);
      state.addRequest(key, [filter]);
      state.timedOut = true;
      state.cancel();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.timedOut),
      });
    });
  });

  group('a subscription after its EOSE', () {
    final url = RelayUrl.parse("wss://relay.example.com");
    final filter = Filter(kinds: [Nip01Event.kTextNoteKind]);
    final key = RelayConnectionKey.anonymous(url);

    RequestState caughtUp() {
      final state = RequestState("caught-up", closeOnEose: false)
        ..addRequest(key, [filter]);
      state.requests[key]!.markCaughtUp();
      return state;
    }

    test('reports eose and is not over', () {
      final state = caughtUp();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
      expect(state.requests[key]!.isDone, isFalse);
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
      state.requests[key]!.markGone();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.disconnected),
      });
    });

    test('is pending again once sent again', () {
      final state = caughtUp();
      state.requests[key]!.markOnItsWay();

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.pending),
      });
    });

    test('a query keeps its eose over a later timeout', () {
      final state = RequestState("query", closeOnEose: true)
        ..addRequest(key, [filter]);
      state.requests[key]!.markCaughtUp();
      state.timedOut = true;

      expect(state.relayOutcomes, {
        url: RelayRequestOutcome(RelayRequestStatus.eose),
      });
      expect(state.didAllRequestsFinish, isTrue);
    });
  });
}
