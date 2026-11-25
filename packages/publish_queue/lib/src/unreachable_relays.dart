import 'package:dostr_core/dostr_core.dart' show RelayUrl;

/// A relay found unreachable while online: how many rounds in a row, the
/// last error, and when it can be tried again.
typedef UnreachableRelay = ({int failures, String error, int retryAt});

/// The relays found unreachable while online, shared by every queued event,
/// so that a dead relay is tried once a round rather than once per event.
class UnreachableRelays {
  final Map<RelayUrl, UnreachableRelay> _relays = {};

  /// [relay] if it waits for its next try at [now].
  UnreachableRelay? waiting(RelayUrl relay, int now) =>
      switch (_relays[relay]) {
        final unreachable? when now < unreachable.retryAt => unreachable,
        _ => null,
      };

  /// Records that [relay] could not be reached at [now] and returns its
  /// failures. Failures reported before its next try belong to the same
  /// round and count once. [delay] gives the wait after a number of failures.
  int failed(
    RelayUrl relay,
    String error,
    int now,
    Duration Function(int failures) delay,
  ) {
    final previous = _relays[relay];
    if (previous != null && now < previous.retryAt) return previous.failures;
    final failures = (previous?.failures ?? 0) + 1;
    _relays[relay] = (
      failures: failures,
      error: error,
      retryAt: now + delay(failures).inMilliseconds,
    );
    return failures;
  }

  void answered(RelayUrl relay) => _relays.remove(relay);

  void clear() => _relays.clear();
}
