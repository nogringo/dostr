import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import '../../../shared/helpers/pausable_timer.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_publish_outcome.dart';
import '../../entities/timeout_pausable.dart';

/// State of one publish. Internal to dostr_core.
class PublishState implements TimeoutPausable {
  /// the event being published, kept to send it again after an auth-required
  /// or a socket that dropped before the OK
  final Nip01Event event;

  /// which identity this publish may be attributed to on the relays (NIP-42)
  final AuthPolicy? auth;

  /// relay urls this publish is sending again to after an auth-required
  /// refusal
  final Set<RelayUrl> retryingAuth = {};

  /// the connection the EVENT was last written on towards each relay
  final Map<RelayUrl, RelayConnectionKey> writtenOn = {};

  final BehaviorSubject<PublishState> _stateUpdatesController =
      BehaviorSubject<PublishState>();

  final StreamController<({RelayUrl url, RelayPublishOutcome outcome})>
  _answers = StreamController();

  /// the whole state each time a relay answers, the latest one replayed to a
  /// new listener
  Stream<PublishState> get stateUpdates => _stateUpdatesController.stream;

  /// the outcome on each relay the event is sent to
  final Map<RelayUrl, RelayPublishOutcome> outcomes;

  /// Whether the publish is over: done or timed out.
  bool get isOver => _answers.isClosed;

  /// Records what [url] did with the event, unless the publish is over.
  void report(RelayUrl url, RelayPublishOutcome outcome) {
    if (!isOver) _answers.add((url: url, outcome: outcome));
  }

  /// Whether [url] was sent the event and has neither answered nor failed.
  bool owesAnswer(RelayUrl url) {
    final outcome = outcomes[url];
    return !isOver &&
        outcome != null &&
        !outcome.okReceived &&
        outcome.failure == null;
  }

  /// Whether every relay answered or failed.
  bool get isDone => outcomes.values.every(
    (outcome) => outcome.okReceived || outcome.failure != null,
  );

  /// completes once the publish is done or timed out
  Future<PublishState> get done => _done.future;

  late final StreamSubscription _answersSubscription;
  late final PausableTimer _timeout = PausableTimer(() {
    if (!isDone) {
      _stateUpdatesController.add(this);
      _dispose();
    }
  });
  bool _isDisposed = false;
  final Completer<PublishState> _done = Completer();

  /// Starts the publish of [event] to [relays], done right away without any.
  PublishState(
    this.event, {
    required Iterable<RelayUrl> relays,
    required Duration timeout,
    this.auth,
  }) : outcomes = {for (final url in relays) url: const RelayPublishOutcome()} {
    _answersSubscription = _answers.stream.listen((response) {
      outcomes[response.url] = response.outcome;
      _stateUpdatesController.add(this);
      _checkDone();
    });
    _timeout.start(timeout);
    _checkDone();
  }

  @override
  void pauseTimeout() => _timeout.pause();

  @override
  void resumeTimeout() => _timeout.resume();

  void _checkDone() {
    if (!isOver && isDone) {
      _stateUpdatesController.add(this);
      _dispose();
    }
  }

  void _dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _timeout.cancel();
    _answersSubscription.cancel();
    if (!_done.isCompleted) {
      _done.complete(this);
    }
    _stateUpdatesController.close();
    _answers.close();
  }
}
