import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import '../connections/relay_connection_key.dart';
import '../helpers/pausable_timer.dart';
import '../helpers/timeout_pausable.dart';
import '../relay_failure.dart';
import 'relay_req_event.dart';
import 'relay_request_outcome.dart';

/// Where a REQ stands on one connection.
enum RelayReqProgress {
  /// Tracked, and waiting for its connection to open.
  connecting,

  /// Written, waiting for a slot, or waiting for its connection to come back.
  pending,

  /// The relay sent its EOSE.
  caughtUp,

  /// The relay asked for authentication. The REQ goes out again once it lands.
  retryingAuth,

  /// The relay ended it with a CLOSED.
  closed,

  /// It could not be sent on this connection.
  notSent,

  /// The connection went away for good before the relay ended it.
  gone,
}

/// A REQ on one connection.
class RelayRequestState {
  /// The connection this request goes out on.
  final RelayConnectionKey key;

  RelayUrl get url => key.url;

  /// Whether the request ends on its EOSE.
  final bool isQuery;

  final List<Filter> filters;

  /// Called by the owning [RequestState] each time the outcome may change.
  void Function()? onOutcomeChanged;

  RelayReqProgress _progress = RelayReqProgress.connecting;
  String? _closedMessage;
  RelayFailure? _failure;

  RelayRequestState(this.key, this.filters, {required this.isQuery});

  RelayReqProgress get progress => _progress;

  /// The message of the relay's CLOSED, kept while it retries authentication.
  String? get closedMessage => _closedMessage;

  /// What kept the request from being sent, while [RelayReqProgress.notSent].
  RelayFailure? get failure => _failure;

  /// Whether the relay is done with the request.
  ///
  /// It is once the relay closed it, never got it, or sent the EOSE of a
  /// query. A subscription goes on after its EOSE.
  bool get isDone => switch (_progress) {
    RelayReqProgress.connecting ||
    RelayReqProgress.pending ||
    RelayReqProgress.retryingAuth => false,
    RelayReqProgress.caughtUp => isQuery,
    RelayReqProgress.closed ||
    RelayReqProgress.notSent ||
    RelayReqProgress.gone => true,
  };

  /// Whether something is still working to send it: its connection is
  /// opening, or the authentication it waits for is under way. Such a request
  /// is never given up as gone.
  bool get isBeingSent =>
      _progress == RelayReqProgress.connecting ||
      _progress == RelayReqProgress.retryingAuth;

  /// Whether a new socket must get the request again.
  ///
  /// A CLOSED stands, unless it asked for an authentication that never landed.
  /// A message too long for the relay stays too long.
  bool get isReplayable => switch (_progress) {
    RelayReqProgress.connecting ||
    RelayReqProgress.pending ||
    RelayReqProgress.retryingAuth ||
    RelayReqProgress.gone => true,
    RelayReqProgress.caughtUp => !isQuery,
    RelayReqProgress.closed => false,
    RelayReqProgress.notSent =>
      _failure?.kind != RelayFailureKind.messageTooLong,
  };

  /// The outcome on this connection.
  ///
  /// A request that [timedOut] or was [cancelled] reports it wherever the
  /// relay had yet to end it, except on a subscription that caught up.
  RelayRequestOutcome outcome({
    required bool timedOut,
    required bool cancelled,
  }) => switch (_progress) {
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
    _ when cancelled => const RelayRequestOutcome(RelayRequestStatus.cancelled),
    RelayReqProgress.connecting ||
    RelayReqProgress.pending ||
    RelayReqProgress.retryingAuth => const RelayRequestOutcome(
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

  /// The request is on its way: written, waiting for a slot, or left to a
  /// connection that replays it once back. Whatever the relay answered before
  /// no longer holds.
  void markOnItsWay() => _moveTo(RelayReqProgress.pending);

  /// The relay sent its EOSE.
  void markCaughtUp() {
    if (_progress == RelayReqProgress.pending ||
        _progress == RelayReqProgress.connecting) {
      _moveTo(RelayReqProgress.caughtUp);
    }
  }

  /// The relay ended the request with a CLOSED carrying [message].
  void markClosed(String? message) {
    if (!isDone) _moveTo(RelayReqProgress.closed, closedMessage: message);
  }

  /// The relay closed the request with [message] for want of an
  /// authentication, which is now under way.
  void markRetryingAuth(String message) {
    if (!isDone) {
      _moveTo(RelayReqProgress.retryingAuth, closedMessage: message);
    }
  }

  /// The authentication will not land, so the CLOSED that asked for it stands.
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
    if (!isDone && !isBeingSent) _moveTo(RelayReqProgress.gone);
  }
}

/// One REQ across all the connections it was sent on.
class RequestState implements TimeoutPausable {
  final StreamController<RelayReqEvent> _received = StreamController();

  /// What the relays send for this request, before it is verified.
  Stream<RelayReqEvent> get received => _received.stream;

  /// Whether the request takes no more events: the relays are done with it, or
  /// it was closed or timed out.
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

  /// Completes once [end] was called.
  Future<void> get ended => _ended.future;

  /// The subscription id sent in REQ and CLOSE (NIP-01).
  final String id;

  /// Only shown in logs.
  final String? name;

  /// Whether it is a query, which ends once every relay sent its EOSE. A
  /// subscription goes on until it is closed.
  final bool closeOnEose;

  /// Which identity the relays may attribute this request to (NIP-42).
  final AuthPolicy? auth;

  bool get isSubscription => !closeOnEose;

  /// The request on each connection it goes out on.
  final Map<RelayConnectionKey, RelayRequestState> requests = {};

  // the connection each relay's outcome reads: the bound one, once an
  // anonymous one handed the request over to it
  final Map<RelayUrl, RelayRequestState> _servingByUrl = {};

  /// How long the request runs before it ends on its own. Null when it never
  /// does.
  final Duration? timeoutDuration;

  bool _timedOut = false;

  /// Whether the request ended on its timeout rather than on the relays.
  bool get timedOut => _timedOut;

  set timedOut(bool value) {
    if (_timedOut == value) return;
    _timedOut = value;
    _refreshRelayOutcomes();
  }

  bool _cancelled = false;

  /// Whether the request was closed before the relays ended it, other than by
  /// its timeout.
  bool get cancelled => _cancelled;

  /// Marks the request as closed by its caller, unless it is over or timed out.
  void cancel() {
    if (_cancelled || _timedOut || isOver) return;
    _cancelled = true;
    _refreshRelayOutcomes();
  }

  /// Called once [timeoutDuration] runs out.
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
      requests.values.every((request) => request.isDone);

  final Map<RelayUrl, RelayRequestOutcome> _relayOutcomes = {};

  Map<RelayUrl, RelayRequestOutcome>? _relayOutcomesSnapshot;

  BehaviorSubject<Map<RelayUrl, RelayRequestOutcome>>? _relayOutcomesSubject;

  bool _relayOutcomesDone = false;

  // copied on demand: a request whose outcomes nobody reads copies nothing
  Map<RelayUrl, RelayRequestOutcome> get _ownRelayOutcomes =>
      _relayOutcomesSnapshot ??= Map.unmodifiable(_relayOutcomes);

  /// The outcome on each relay, as it stands now.
  ///
  /// A relay whose anonymous connection handed the request over to a bound one
  /// reports the outcome on the bound one.
  Map<RelayUrl, RelayRequestOutcome> get relayOutcomes => _ownRelayOutcomes;

  /// [relayOutcomes] on every change, starting with what it holds now, and
  /// closed once the request is over.
  Stream<Map<RelayUrl, RelayRequestOutcome>> get relayOutcomesStream {
    final subject = _relayOutcomesSubject ??= BehaviorSubject.seeded(
      _ownRelayOutcomes,
    );
    // nothing is left to close a subject created after the end, and a closed
    // one still replays its last value
    if (_relayOutcomesDone) {
      subject.close();
    }
    return subject.stream;
  }

  /// Recomputes every relay, for a change that reaches all of them at once.
  void _refreshRelayOutcomes() {
    var changed = false;
    for (final url in _servingByUrl.keys) {
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

  /// Reads the outcome of [url] from the connection serving it, and returns
  /// whether that outcome changed.
  bool _recomputeRelayOutcome(RelayUrl url) {
    final outcome = _servingByUrl[url]!.outcome(
      timedOut: timedOut,
      cancelled: cancelled,
    );
    if (_relayOutcomes[url] == outcome) {
      return false;
    }
    _relayOutcomes[url] = outcome;
    return true;
  }

  void _publishRelayOutcomes() {
    _relayOutcomesSnapshot = null;
    final subject = _relayOutcomesSubject;
    if (subject != null && !subject.isClosed) {
      subject.add(_ownRelayOutcomes);
    }
  }

  /// The request on [key], tracked from now on if it was not yet. A new
  /// connection to a relay already tracked is the one the request was handed
  /// over to, and serves the relay from now on.
  RelayRequestState addRequest(RelayConnectionKey key, List<Filter> filters) {
    final tracked = requests[key];
    if (tracked != null) return tracked;
    final request = RelayRequestState(key, filters, isQuery: closeOnEose)
      ..onOutcomeChanged = () => _onRelayRequestChanged(key.url);
    requests[key] = request;
    _servingByUrl[key.url] = request;
    _onRelayRequestChanged(key.url);
    return request;
  }

  /// Stops the timeout and closes [relayOutcomesStream]. A query ends here once
  /// its events are all delivered, rather than on [close].
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
