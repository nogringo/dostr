import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import '../../../shared/helpers/pausable_timer.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_publish_outcome.dart';
import '../../entities/timeout_pausable.dart';

/// Where a publish stands on a relay that has yet to answer it.
enum RelayPublishProgress {
  /// waiting for its connection to open or come back
  connecting,

  /// written on its connection, waiting for the OK
  written,

  /// refused for want of an identity, moving to a connection bound to one
  retryingAuth,
}

/// A publish on one relay. Internal to dostr_core.
class RelayPublishState {
  final RelayUrl url;

  /// the connection the EVENT goes out on, bound once the relay asked for an
  /// identity, null when the identity its `AuthPolicy` requires cannot sign
  RelayConnectionKey? key;

  /// where it stands while [isPending]
  RelayPublishProgress progress = RelayPublishProgress.connecting;

  RelayPublishOutcome _outcome = const RelayPublishOutcome.pending();

  RelayPublishState(this.url, this.key);

  RelayPublishOutcome get outcome => _outcome;

  /// Whether the relay has yet to answer.
  bool get isPending => _outcome.isPending;

  /// Whether the publish still needs the connection behind [connection].
  bool isPendingOn(RelayConnectionKey connection) =>
      isPending && key == connection;

  /// Whether the EVENT was written on [connection] and is unanswered there.
  bool isOwedOn(RelayConnectionKey connection) =>
      isPendingOn(connection) && progress == RelayPublishProgress.written;
}

/// State of one publish. Internal to dostr_core.
class PublishState implements TimeoutPausable {
  /// the event being published, kept to send it again after an auth-required
  /// or a socket that dropped before the OK
  final Nip01Event event;

  /// which identity this publish may be attributed to on the relays (NIP-42)
  final AuthPolicy? auth;

  /// each relay the event goes to, by url
  final Map<RelayUrl, RelayPublishState> relays;

  final _outcomesStream = BehaviorSubject<Map<RelayUrl, RelayPublishOutcome>>();

  final _done = Completer<Map<RelayUrl, RelayPublishOutcome>>();

  Map<RelayUrl, RelayPublishOutcome>? _outcomes;

  late final PausableTimer _timeout = PausableTimer(_timeOut);

  /// Starts the publish of [event] to [relays], done right away without any.
  PublishState(
    this.event, {
    required Iterable<RelayUrl> relays,
    required Duration timeout,
    this.auth,
  }) : relays = {
         for (final url in relays)
           url: RelayPublishState(url, RelayConnectionKey.forAuth(url, auth)),
       } {
    _timeout.start(timeout);
    _finishIfAnswered();
  }

  @override
  void pauseTimeout() => _timeout.pause();

  @override
  void resumeTimeout() => _timeout.resume();

  /// Whether the publish is over: every relay answered, or it timed out.
  bool get isOver => _done.isCompleted;

  /// the outcome on each relay, as it stands now
  Map<RelayUrl, RelayPublishOutcome> get outcomes =>
      _outcomes ??= Map.unmodifiable({
        for (final relay in relays.values) relay.url: relay.outcome,
      });

  /// [outcomes] each time a relay answers, the latest one replayed to a new
  /// listener, closed once the publish is over
  Stream<Map<RelayUrl, RelayPublishOutcome>> get outcomesStream =>
      _outcomesStream.stream;

  /// [outcomes] once the publish is over
  Future<Map<RelayUrl, RelayPublishOutcome>> get done => _done.future;

  /// Ends the publish on [url] with [outcome], unless the relay already
  /// answered or the publish is over: the first answer stands.
  void end(RelayUrl url, RelayPublishOutcome outcome) {
    final relay = relays[url];
    if (isOver || relay == null || !relay.isPending) return;
    relay._outcome = outcome;
    _changed();
    _finishIfAnswered();
  }

  void _changed() {
    _outcomes = null;
    _outcomesStream.add(outcomes);
  }

  void _finishIfAnswered() {
    if (!relays.values.any((relay) => relay.isPending)) _finish();
  }

  void _timeOut() {
    if (isOver) return;
    for (final relay in relays.values.where((relay) => relay.isPending)) {
      relay._outcome = const RelayPublishOutcome.timedOut();
    }
    _changed();
    _finish();
  }

  void _finish() {
    if (isOver) return;
    _timeout.cancel();
    _done.complete(outcomes);
    unawaited(_outcomesStream.close());
  }
}
