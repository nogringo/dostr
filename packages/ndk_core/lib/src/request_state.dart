import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../domain_layer/entities/filter.dart';
import '../domain_layer/entities/nip_01_event.dart';
import '../domain_layer/entities/auth_handler.dart';
import '../domain_layer/entities/auth_policy.dart';
import '../domain_layer/entities/relay_connection_key.dart';
import '../domain_layer/entities/relay_request_outcome.dart';

/// Single relay request state
class RelayRequestState {
  /// connection this request was sent on
  final RelayConnectionKey key;

  /// url of the relay this request was sent to
  String get url => key.url;

  /// called by the owning [RequestState] whenever a field the outcome is
  /// derived from changes, so the outcome never has to be derived on read
  void Function()? onOutcomeChanged;

  bool _receivedEOSE = false;

  /// did the relay give everything it stored
  bool get receivedEOSE => _receivedEOSE;

  set receivedEOSE(bool value) {
    if (_receivedEOSE == value) return;
    _receivedEOSE = value;
    onOutcomeChanged?.call();
  }

  bool _receivedClosed = false;

  /// did the relay end the request itself
  bool get receivedClosed => _receivedClosed;

  set receivedClosed(bool value) {
    if (_receivedClosed == value) return;
    _receivedClosed = value;
    onOutcomeChanged?.call();
  }

  String? _closedMessage;

  /// message the relay sent with its CLOSED, null when it sent none
  String? get closedMessage => _closedMessage;

  set closedMessage(String? value) {
    if (_closedMessage == value) return;
    _closedMessage = value;
    onOutcomeChanged?.call();
  }

  bool _connectionGone = false;

  /// set when the connection was gone before the relay ended the request
  bool get connectionGone => _connectionGone;

  set connectionGone(bool value) {
    if (_connectionGone == value) return;
    _connectionGone = value;
    onOutcomeChanged?.call();
  }

  bool _notSent = false;

  /// set when the request could not be sent on this connection
  bool get notSent => _notSent;

  String? _notSentReason;

  /// what kept the request from being sent, see [markNotSent]
  String? get notSentReason => _notSentReason;

  bool _retryingAuth = false;

  /// set while this connection authenticates to satisfy the request: the relay
  /// closed it, but it is on its way back and must not count as finished
  bool get retryingAuth => _retryingAuth;

  set retryingAuth(bool value) {
    if (_retryingAuth == value) return;
    _retryingAuth = value;
    onOutcomeChanged?.call();
  }

  List<Filter> filters;

  /// default const
  RelayRequestState(this.key, this.filters);

  /// The relay ended the request with a CLOSED carrying [message].
  ///
  /// Both at once, so the outcome is never observed as a CLOSED stripped of
  /// the reason the relay gave for it.
  void markClosed(String? message) {
    if (_receivedClosed && _closedMessage == message) return;
    _receivedClosed = true;
    _closedMessage = message;
    onOutcomeChanged?.call();
  }

  /// The request could not be sent on this connection, because of [reason].
  void markNotSent(String reason) {
    if (_notSent && _notSentReason == reason) return;
    _notSent = true;
    _notSentReason = reason;
    onOutcomeChanged?.call();
  }

  /// The request is on its way to the relay again, so whatever ended it the
  /// last time no longer holds.
  void markSent() {
    if (!_receivedClosed &&
        _closedMessage == null &&
        !_connectionGone &&
        !_notSent &&
        !_retryingAuth) {
      return;
    }
    _receivedClosed = false;
    _closedMessage = null;
    _connectionGone = false;
    _notSent = false;
    _notSentReason = null;
    _retryingAuth = false;
    onOutcomeChanged?.call();
  }
}

/// State per request for multiple relays
class RequestState implements TimeoutPausable {
  /// [networkController] used by engines to write their response
  StreamController<Nip01Event> networkController =
      StreamController<Nip01Event>();

  final Completer<void> _ended = Completer<void>();

  Timer? _timeout;
  DateTime? _timeoutStartedAt;
  Duration? _timeoutLeftAtStart;
  Duration? _remainingTimeout;
  int _timeoutPauses = 0;

  /// completes once [end] was called
  Future<void> get ended => _ended.future;

  /// subscription id sent to relays in REQ/CLOSE (NIP-01)
  final String id;

  /// request name, only shown in logs
  final String? name;

  /// should it close on receiving EOSE?
  final bool closeOnEose;

  /// which identity this request may be attributed to on the relays (NIP-42)
  final AuthPolicy? auth;

  /// is this a subscription?
  bool get isSubscription => !closeOnEose;

  ///! our requests tracking obj
  // key is the connection the request was sent on, value is RelayRequestState
  Map<RelayConnectionKey, RelayRequestState> requests = {};

  /// send paths still working out which connection to use, before they show up
  /// in [requests]. The relay that answers first must not look like the only
  /// one this request ever had, or the stream closes on the others
  int pendingConnections = 0;

  // the connections of one relay, so collapsing a url into its outcome reads
  // them instead of scanning every connection of the request
  final Map<String, List<RelayRequestState>> _requestsByUrl = {};

  /// timeout duration, closes all streams
  final Duration? timeoutDuration;

  bool _timedOut = false;

  /// set when the request ended on its timeout instead of on the relays
  bool get timedOut => _timedOut;

  set timedOut(bool value) {
    if (_timedOut == value) return;
    _timedOut = value;
    _refreshRelayOutcomes();
  }

  /// called when timeout is triggered
  Function(RequestState)? onTimeout;

  /// Creates a new [RequestState] instance
  RequestState(
    this.id, {
    this.name,
    required this.closeOnEose,
    this.auth,
    this.timeoutDuration,
  }) {
    final timeout = timeoutDuration;
    if (timeout != null) {
      _startTimeout(timeout);
    }
  }

  /// A query, ended once every relay sent its EOSE.
  RequestState.query(
    String id, {
    String? name,
    AuthPolicy? auth,
    Duration? timeout,
  }) : this(
         id,
         name: name,
         closeOnEose: true,
         auth: auth,
         timeoutDuration: timeout,
       );

  /// A subscription, which runs until closed.
  RequestState.subscription(
    String id, {
    String? name,
    AuthPolicy? auth,
    Duration? timeout,
  }) : this(
         id,
         name: name,
         closeOnEose: false,
         auth: auth,
         timeoutDuration: timeout,
       );

  void _startTimeout(Duration duration) {
    _timeoutStartedAt = DateTime.now();
    _timeoutLeftAtStart = duration;
    _timeout = Timer(duration, () {
      timedOut = true;
      onTimeout?.call(this);
      close();
    });
  }

  /// Pauses the timeout timer. Call this before signing starts.
  @override
  void pauseTimeout() {
    _timeoutPauses++;
    if (_timeoutPauses > 1 || _timeout == null || !_timeout!.isActive) return;

    final elapsed = DateTime.now().difference(_timeoutStartedAt!);
    final remaining = _timeoutLeftAtStart! - elapsed;
    _remainingTimeout = remaining.isNegative ? Duration.zero : remaining;
    _timeout!.cancel();
    _timeout = null;
  }

  /// Resumes the timeout timer. Call this after signing completes.
  @override
  void resumeTimeout() {
    if (_timeoutPauses == 0) return;
    _timeoutPauses--;
    final remaining = _remainingTimeout;
    if (_timeoutPauses > 0 || remaining == null) return;
    _remainingTimeout = null;
    _startTimeout(remaining);
  }

  /// checks if all requests finished (received EOSE or CLOSED, or could not be
  /// sent)
  bool get didAllRequestsFinish =>
      pendingConnections == 0 &&
      requests.values.every(
        (element) =>
            (element.receivedEOSE ||
                element.receivedClosed ||
                element.notSent) &&
            !element.retryingAuth,
      );

  final Map<String, RelayRequestOutcome> _relayOutcomes = {};

  Map<String, RelayRequestOutcome>? _relayOutcomesSnapshot;

  BehaviorSubject<Map<String, RelayRequestOutcome>>? _relayOutcomesSubject;

  bool _relayOutcomesDone = false;

  /// [_relayOutcomes] as it is handed out, built on demand: a request whose
  /// outcomes nobody reads or watches copies nothing.
  Map<String, RelayRequestOutcome> get _ownRelayOutcomes =>
      _relayOutcomesSnapshot ??= Map.unmodifiable(_relayOutcomes);

  /// What the request ended with on each relay it was sent to, as it stands now
  ///
  /// Keyed by relay url: several connections to one relay collapse into the
  /// outcome that comes first in [RelayRequestStatus].
  Map<String, RelayRequestOutcome> get relayOutcomes => _ownRelayOutcomes;

  /// [relayOutcomes] on every change, starting with what it holds right now,
  /// and closed once the request is over.
  ///
  /// Late subscribers get the current outcomes instead of missing everything
  /// the relays answered before they listened.
  Stream<Map<String, RelayRequestOutcome>> get relayOutcomesStream {
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

  void _onRelayRequestChanged(String url) {
    if (_recomputeRelayOutcome(url)) {
      _publishRelayOutcomes();
    }
  }

  /// Collapses the connections to [url] into its outcome, returning whether
  /// that outcome moved.
  bool _recomputeRelayOutcome(String url) {
    RelayRequestOutcome? collapsed;
    for (final request in _requestsByUrl[url] ?? const <RelayRequestState>[]) {
      final outcome = _outcomeOf(request);
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

  RelayRequestOutcome _outcomeOf(RelayRequestState request) {
    if (request.retryingAuth) {
      return const RelayRequestOutcome(RelayRequestStatus.pending);
    }
    if (request.receivedEOSE) {
      return const RelayRequestOutcome(RelayRequestStatus.eose);
    }
    if (request.receivedClosed) {
      return RelayRequestOutcome(
        RelayRequestStatus.closed,
        message: request.closedMessage,
      );
    }
    if (request.notSent) {
      return RelayRequestOutcome(
        RelayRequestStatus.notSent,
        message: request.notSentReason,
      );
    }
    if (request.connectionGone) {
      return const RelayRequestOutcome(RelayRequestStatus.disconnected);
    }
    if (timedOut) {
      return const RelayRequestOutcome(RelayRequestStatus.timedOut);
    }
    return const RelayRequestOutcome(RelayRequestStatus.pending);
  }

  /// Adds single relay request to the state
  void addRequest(RelayConnectionKey key, List<Filter> filters) {
    if (requests.containsKey(key)) return;
    _trackRequest(RelayRequestState(key, filters));
  }

  void _trackRequest(RelayRequestState request) {
    request.onOutcomeChanged = () => _onRelayRequestChanged(request.url);
    requests[request.key] = request;
    _requestsByUrl.putIfAbsent(request.url, () => []).add(request);
    _onRelayRequestChanged(request.url);
  }

  /// Closes the network stream if the request was not sent to any relay.
  /// Engines call this once they are done dispatching: without a relay to
  /// answer, nothing would end the request but its timeout. A send path that
  /// is still working out its connection still counts, it may yet register one.
  void closeIfNoRelays() {
    if (requests.isNotEmpty ||
        pendingConnections > 0 ||
        networkController.isClosed) {
      return;
    }
    networkController.close();
  }

  /// Stops the timeout and closes [relayOutcomesStream]. A query ends here
  /// once its events are all delivered, rather than on [close].
  void end() {
    if (_ended.isCompleted) return;
    _stopTimeout();
    _relayOutcomesDone = true;
    _relayOutcomesSubject?.close();
    _ended.complete();
  }

  /// closes all streams
  Future<void> close() async {
    _stopTimeout();
    await networkController.close();
    end();
  }

  void _stopTimeout() {
    _timeout?.cancel();
    _timeout = null;
    _remainingTimeout = null;
  }
}
