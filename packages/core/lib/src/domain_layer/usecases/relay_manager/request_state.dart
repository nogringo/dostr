import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import '../../../shared/helpers/pausable_timer.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_failure.dart';
import '../../entities/relay_req_event.dart';
import '../../entities/relay_request_outcome.dart';
import '../../entities/timeout_pausable.dart';

/// Where a REQ stands on one connection.
enum RelayReqProgress {
  /// not answered yet: waiting for its connection or a slot, or written
  pending,

  /// the relay sent its EOSE
  caughtUp,

  /// the relay asked for an authentication that is under way, and gets the
  /// REQ again once it lands
  retryingAuth,

  /// the relay ended it with a CLOSED
  closed,

  /// it could not be sent on this connection
  notSent,

  /// the connection went away for good before the relay ended it
  gone,
}

/// A REQ on one connection.
class RelayRequestState {
  /// connection this request was sent on
  final RelayConnectionKey key;

  /// the relay this request was sent to
  RelayUrl get url => key.url;

  /// whether the request ends on its EOSE
  final bool isQuery;

  final List<Filter> filters;

  /// called by the owning [RequestState] whenever the outcome may have moved,
  /// so the outcome never has to be derived on read
  void Function()? onOutcomeChanged;

  RelayReqProgress _progress = RelayReqProgress.pending;
  String? _closedMessage;
  RelayFailure? _failure;

  RelayRequestState(this.key, this.filters, {required this.isQuery});

  RelayReqProgress get progress => _progress;

  /// message the relay sent with its CLOSED, kept while [retryingAuth]
  String? get closedMessage => _closedMessage;

  /// what kept the request from being sent, while [RelayReqProgress.notSent]
  RelayFailure? get failure => _failure;

  /// Whether the relay is done with the request: it ended it, never got it, or
  /// sent the EOSE of a query. A subscription outlives its EOSE.
  bool get isDone => switch (_progress) {
    RelayReqProgress.pending || RelayReqProgress.retryingAuth => false,
    RelayReqProgress.caughtUp => isQuery,
    RelayReqProgress.closed ||
    RelayReqProgress.notSent ||
    RelayReqProgress.gone => true,
  };

  /// Whether a socket that comes back owes the request again: a CLOSED stands,
  /// unless it asked for an authentication that never landed, and a message
  /// too long for the relay stays too long.
  bool get isReplayable => switch (_progress) {
    RelayReqProgress.pending ||
    RelayReqProgress.retryingAuth ||
    RelayReqProgress.gone => true,
    RelayReqProgress.caughtUp => !isQuery,
    RelayReqProgress.closed => false,
    RelayReqProgress.notSent =>
      _failure?.kind != RelayFailureKind.messageTooLong,
  };

  RelayRequestOutcome outcome({required bool timedOut}) => switch (_progress) {
    RelayReqProgress.retryingAuth => const RelayRequestOutcome(
      RelayRequestStatus.pending,
    ),
    RelayReqProgress.caughtUp when isQuery => const RelayRequestOutcome(
      RelayRequestStatus.eose,
    ),
    RelayReqProgress.closed => RelayRequestOutcome(
      RelayRequestStatus.closed,
      message: _closedMessage,
    ),
    RelayReqProgress.notSent => RelayRequestOutcome(
      RelayRequestStatus.notSent,
      failure: _failure,
    ),
    RelayReqProgress.gone => const RelayRequestOutcome(
      RelayRequestStatus.disconnected,
    ),
    _ when timedOut => const RelayRequestOutcome(RelayRequestStatus.timedOut),
    RelayReqProgress.caughtUp => const RelayRequestOutcome(
      RelayRequestStatus.eose,
    ),
    RelayReqProgress.pending => const RelayRequestOutcome(
      RelayRequestStatus.pending,
    ),
  };

  void _moveTo(
    RelayReqProgress progress, {
    String? closedMessage,
    RelayFailure? failure,
  }) {
    if (_progress == progress &&
        _closedMessage == closedMessage &&
        _failure == failure) {
      return;
    }
    _progress = progress;
    _closedMessage = closedMessage;
    _failure = failure;
    onOutcomeChanged?.call();
  }

  /// The relay sent its EOSE.
  void markCaughtUp() {
    if (_progress == RelayReqProgress.pending) {
      _moveTo(RelayReqProgress.caughtUp);
    }
  }

  /// The relay ended the request with a CLOSED carrying [message].
  void markClosed(String? message) {
    if (!isDone) _moveTo(RelayReqProgress.closed, closedMessage: message);
  }

  /// The relay closed the request for want of an authentication, which is
  /// now under way.
  void markRetryingAuth() {
    if (_progress == RelayReqProgress.closed) {
      _moveTo(RelayReqProgress.retryingAuth, closedMessage: _closedMessage);
    }
  }

  /// The authentication will not land: the CLOSED that asked for it stands.
  void endAuthRetry() {
    if (_progress == RelayReqProgress.retryingAuth) {
      _moveTo(RelayReqProgress.closed, closedMessage: _closedMessage);
    }
  }

  /// The request could not be sent on this connection, because of [failure].
  void markNotSent(RelayFailure failure) =>
      _moveTo(RelayReqProgress.notSent, failure: failure);

  /// The connection went away for good while the relay still owed an answer.
  void markGone() {
    if (!isDone && _progress != RelayReqProgress.retryingAuth) {
      _moveTo(RelayReqProgress.gone);
    }
  }

  /// The request goes to the relay again, written now or queued for a slot,
  /// so nothing the relay answered the last time holds anymore.
  void forgetAnswers() => _moveTo(RelayReqProgress.pending);
}

/// State per request for multiple relays
class RequestState implements TimeoutPausable {
  final StreamController<RelayReqEvent> _received = StreamController();

  /// what the relays send for this request, before it is verified
  Stream<RelayReqEvent> get received => _received.stream;

  /// Whether the request takes no more events: the relays are done with it,
  /// or it was closed or timed out.
  bool get isOver => _received.isClosed;

  /// Hands [event] to [received]. Only call it while the request is not over.
  void deliver(RelayReqEvent event) => _received.add(event);

  /// Stops taking events, once the relays are done with the request.
  void finish() => unawaited(_received.close());

  final Completer<void> _ended = Completer<void>();

  late final PausableTimer _timeout = PausableTimer(() {
    timedOut = true;
    onTimeout?.call(this);
    close();
  });

  /// completes once [end] was called
  Future<void> get ended => _ended.future;

  /// subscription id sent to relays in REQ/CLOSE (NIP-01)
  final String id;

  /// request name, only shown in logs
  final String? name;

  /// whether it is a query, which ends once every relay sent its EOSE, rather
  /// than a subscription
  final bool closeOnEose;

  /// which identity this request may be attributed to on the relays (NIP-42)
  final AuthPolicy? auth;

  bool get isSubscription => !closeOnEose;

  /// the request on each connection it was sent on
  final Map<RelayConnectionKey, RelayRequestState> requests = {};

  /// send paths still working out which connection to use, before they show up
  /// in [requests]. The relay that answers first must not look like the only
  /// one this request ever had, or the stream closes on the others
  int _pendingConnections = 0;

  void beginPendingConnection() => _pendingConnections++;

  void endPendingConnection() => _pendingConnections--;

  bool get hasPendingConnections => _pendingConnections > 0;

  // the connections of one relay, so collapsing a url into its outcome reads
  // them instead of scanning every connection of the request
  final Map<RelayUrl, List<RelayRequestState>> _requestsByUrl = {};

  /// how long the request runs before it ends on its own, null when it never
  /// does
  final Duration? timeoutDuration;

  bool _timedOut = false;

  /// set when the request ended on its timeout instead of on the relays
  bool get timedOut => _timedOut;

  set timedOut(bool value) {
    if (_timedOut == value) return;
    _timedOut = value;
    _refreshRelayOutcomes();
  }

  /// told once [timeoutDuration] ran out
  void Function(RequestState)? onTimeout;

  RequestState(
    this.id, {
    this.name,
    required this.closeOnEose,
    this.auth,
    this.timeoutDuration,
  }) {
    final timeout = timeoutDuration;
    if (timeout != null) _timeout.start(timeout);
  }

  @override
  void pauseTimeout() => _timeout.pause();

  @override
  void resumeTimeout() => _timeout.resume();

  /// Whether every relay is done with the request, see
  /// [RelayRequestState.isDone].
  bool get didAllRequestsFinish =>
      _pendingConnections == 0 &&
      requests.values.every((request) => request.isDone);

  final Map<RelayUrl, RelayRequestOutcome> _relayOutcomes = {};

  Map<RelayUrl, RelayRequestOutcome>? _relayOutcomesSnapshot;

  BehaviorSubject<Map<RelayUrl, RelayRequestOutcome>>? _relayOutcomesSubject;

  bool _relayOutcomesDone = false;

  /// [_relayOutcomes] as it is handed out, built on demand: a request whose
  /// outcomes nobody reads or watches copies nothing.
  Map<RelayUrl, RelayRequestOutcome> get _ownRelayOutcomes =>
      _relayOutcomesSnapshot ??= Map.unmodifiable(_relayOutcomes);

  /// What the request ended with on each relay it was sent to, as it stands now
  ///
  /// Keyed by relay url: several connections to one relay collapse into the
  /// outcome that comes first in [RelayRequestStatus].
  Map<RelayUrl, RelayRequestOutcome> get relayOutcomes => _ownRelayOutcomes;

  /// [relayOutcomes] on every change, starting with what it holds right now,
  /// and closed once the request is over.
  ///
  /// Late subscribers get the current outcomes instead of missing everything
  /// the relays answered before they listened.
  Stream<Map<RelayUrl, RelayRequestOutcome>> get relayOutcomesStream {
    final subject = _relayOutcomesSubject ??= BehaviorSubject.seeded(
      _ownRelayOutcomes,
    );
    // asked for once the request is over: nothing is left to close a subject
    // created this late, and a closed one still replays what it ended on
    if (_relayOutcomesDone) {
      subject.close();
    }
    return subject.stream;
  }

  /// Recomputes every relay, for a change that reaches all of them at once.
  void _refreshRelayOutcomes() {
    var changed = false;
    for (final url in _requestsByUrl.keys) {
      changed = _recomputeRelayOutcome(url) || changed;
    }
    if (changed) {
      _publishRelayOutcomes();
    }
  }

  void _onRelayRequestChanged(RelayUrl url) {
    if (_recomputeRelayOutcome(url)) {
      _publishRelayOutcomes();
    }
  }

  /// Collapses the connections to [url] into its outcome, returning whether
  /// that outcome moved.
  bool _recomputeRelayOutcome(RelayUrl url) {
    RelayRequestOutcome? collapsed;
    for (final request in _requestsByUrl[url] ?? const <RelayRequestState>[]) {
      final outcome = request.outcome(timedOut: timedOut);
      if (collapsed == null || outcome.status.index < collapsed.status.index) {
        collapsed = outcome;
      }
    }
    if (collapsed == null) {
      return _relayOutcomes.remove(url) != null;
    }
    if (_relayOutcomes[url] == collapsed) {
      return false;
    }
    _relayOutcomes[url] = collapsed;
    return true;
  }

  void _publishRelayOutcomes() {
    _relayOutcomesSnapshot = null;
    final subject = _relayOutcomesSubject;
    if (subject != null && !subject.isClosed) {
      subject.add(_ownRelayOutcomes);
    }
  }

  /// Tracks the request on [key], unless it already is.
  void addRequest(RelayConnectionKey key, List<Filter> filters) {
    if (requests.containsKey(key)) return;
    _trackRequest(RelayRequestState(key, filters, isQuery: closeOnEose));
  }

  void _trackRequest(RelayRequestState request) {
    request.onOutcomeChanged = () => _onRelayRequestChanged(request.url);
    requests[request.key] = request;
    _requestsByUrl.putIfAbsent(request.url, () => []).add(request);
    _onRelayRequestChanged(request.url);
  }

  /// Stops the timeout and closes [relayOutcomesStream]. A query ends here
  /// once its events are all delivered, rather than on [close].
  void end() {
    if (_ended.isCompleted) return;
    _timeout.cancel();
    _relayOutcomesDone = true;
    _relayOutcomesSubject?.close();
    _ended.complete();
  }

  /// Stops taking events, and ends the request.
  Future<void> close() async {
    _timeout.cancel();
    await _received.close();
    end();
  }
}
