import 'dart:async';

import 'package:dostr_broadcast_queue/dostr_broadcast_queue.dart';
import 'package:dostr_core/dostr_core.dart';

/// Test double for [BroadcastFn]. Records every call and lets a test dictate
/// each relay's answer, throw, or park an attempt mid-flight.
class FakeBroadcaster {
  /// What each relay answers. A relay without one is left out of the result,
  /// as one that did not answer.
  final Map<String, RelayPublishOutcome> responders = {};

  final List<({Nip01Event event, List<RelayUrl> relays, String? account})>
  calls = [];

  /// Thrown by every call until cleared.
  Object? error;

  /// When set, every call parks on this gate instead of answering, letting a
  /// test drive an attempt that is mid-flight.
  Completer<Map<RelayUrl, RelayPublishOutcome>>? gate;

  BroadcastFn get fn => (event, relays, {account}) async {
    calls.add((event: event, relays: List.of(relays), account: account));
    if (error != null) throw error!;
    if (gate != null) return gate!.future;
    return {for (final relay in relays) relay: ?responders[relay]};
  };

  void ack(String relay) => ackAll([relay]);

  void ackAll(List<String> relays) {
    for (final relay in relays) {
      responders[relay] = const RelayPublishOutcome.accepted();
    }
  }

  void fail(
    String relay, {
    RelayFailureKind kind = RelayFailureKind.unreachable,
    String detail = 'connection refused',
  }) {
    responders[relay] = RelayPublishOutcome.failed(RelayFailure(kind, detail));
  }

  void refuse(String relay, {required String message}) {
    responders[relay] = RelayPublishOutcome.refused(message);
  }

  void timeOut(String relay) {
    responders[relay] = const RelayPublishOutcome.timedOut();
  }
}
