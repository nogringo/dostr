part of '../relay_manager.dart';

/// Opens [RelayReq]s: NIP-01 REQs on relays the caller picks.
///
/// This is the layer below `Requests`: no cache, no outbox routing, no merging
/// of identical requests and no pagination.
class RelayReqs {
  final RelayManager _relayManager;
  final EventVerifier _eventVerifier;
  final VerifiedEventMemCache _verifiedEventCache;

  RelayReqs({
    required RelayManager relayManager,
    required EventVerifier eventVerifier,
    VerifiedEventMemCache? verifiedEventCache,
  }) : _relayManager = relayManager,
       _eventVerifier = eventVerifier,
       _verifiedEventCache = verifiedEventCache ?? VerifiedEventMemCache();

  /// Forgets which signatures were already checked.
  void clearVerifiedEventCache() => _verifiedEventCache.clear();

  /// Closes the REQ open under [id] on this manager, whatever [RelayReqs]
  /// opened it, like [RelayReq.close]. Says whether there was one.
  Future<bool> close(String id) async {
    final req = _relayManager._openReqs[id];
    if (req == null) return false;
    await req.close();
    return true;
  }

  /// Closes every REQ open on this manager, whatever [RelayReqs] opened them.
  Future<void> closeAll() async {
    await Future.wait([
      for (final req in _relayManager._openReqs.values.toList()) req.close(),
    ]);
  }

  /// Opens a REQ.
  ///
  /// With [relays], each of them gets its filters and the request is sealed
  /// right away. Without, add relays with [RelayReq.send], then
  /// [RelayReq.seal]: the request is held open until then.
  ///
  /// [closeOnEose] makes it a query, ended once every relay sent its EOSE.
  /// Otherwise it is a subscription, which lives until [RelayReq.close].
  /// [timeout] ends it after that long, not counting NIP-42 authentication.
  /// [name] only shows in logs.
  RelayReq req({
    Map<String, List<Filter>>? relays,
    String? id,
    String? name,
    bool closeOnEose = true,
    AuthPolicy? auth,
    Duration? timeout,
  }) {
    final reqId = id ?? Helpers.getSecureRandomHex(16);
    if (reqId.isEmpty || reqId.length > 64) {
      throw ArgumentError.value(id, 'id', 'must be 1 to 64 characters long');
    }
    if (_relayManager.globalState.inFlightRequests.containsKey(reqId)) {
      throw StateError('a request with id $reqId is already in flight');
    }

    final req = RelayReq._(
      RequestState(
        reqId,
        name: name,
        closeOnEose: closeOnEose,
        auth: auth,
        timeoutDuration: timeout,
      ),
      relayManager: _relayManager,
      eventVerifier: _eventVerifier,
      verifiedEventCache: _verifiedEventCache,
    );
    if (relays != null) {
      try {
        relays.forEach(req.send);
      } catch (_) {
        unawaited(req.close());
        rethrow;
      }
      req.seal();
    }
    return req;
  }
}

/// One REQ on the relays its caller picked, opened by [RelayReqs.req].
///
/// [events] are verified and carry their relay in [Nip01Event.sources]. They
/// are not deduplicated: an event two relays hold arrives twice.
class RelayReq {
  final RequestState _state;
  final RelayManager _relayManager;
  late final StreamController<Nip01Event> _events = StreamController(
    onCancel: close,
  );
  late final Future<Map<String, RelayRequestOutcome>> _done;
  final Set<String> _sentTo = {};
  bool _sealed = false;
  Future<void>? _closing;

  RelayReq._(
    this._state, {
    required RelayManager relayManager,
    required EventVerifier eventVerifier,
    required VerifiedEventMemCache verifiedEventCache,
  }) : _relayManager = relayManager {
    final inFlight = relayManager.globalState.inFlightRequests;
    final open = relayManager._openReqs;
    _state.onTimeout = (_) => close();
    // released by seal: until then, more relays may come
    relayManager._beginPendingConnection(_state);
    inFlight[id] = _state;
    open[id] = this;
    _done = _state.controller.done.then((_) => _state.relayOutcomes);

    VerifyEventStream(
      unverifiedStreamInput: _state.networkController.stream,
      eventVerifier: eventVerifier,
      verifiedEventCache: verifiedEventCache,
    )().listen(
      (event) {
        if (!_events.isClosed) _events.add(event);
      },
      onDone: () {
        unawaited(_events.close());
        unawaited(_state.controller.close());
        if (identical(inFlight[id], _state)) inFlight.remove(id);
        if (identical(open[id], this)) open.remove(id);
      },
    );
  }

  /// NIP-01 subscription id
  String get id => _state.id;

  bool get closeOnEose => _state.closeOnEose;

  /// Single-subscription: cancelling it closes the request, like [close].
  Stream<Nip01Event> get events => _events.stream;

  /// What the request ended with on each relay so far, keyed by relay url.
  Map<String, RelayRequestOutcome> get outcomes => _state.relayOutcomes;

  /// [outcomes] on every change, closed once the request is over.
  Stream<Map<String, RelayRequestOutcome>> get outcomesStream =>
      _state.relayOutcomesStream;

  /// [outcomes] once every relay ended the request, on timeout, or on [close].
  Future<Map<String, RelayRequestOutcome>> get done => _done;

  /// Whether the request ended on its timeout.
  bool get timedOut => _state.timedOut;

  /// Sends [filters] to [relayUrl] on the connection the request's
  /// [AuthPolicy] allows, and says whether it went out: once the request is
  /// over, nothing is sent. One call per relay.
  ///
  /// A relay sent to after [seal] still has to answer before the request ends.
  bool send(String relayUrl, List<Filter> filters) {
    if (!_relayManager._isStillInFlight(_state) ||
        _state.networkController.isClosed) {
      return false;
    }
    if (!_sentTo.add(RelayConnectionKey.anonymous(relayUrl).url)) {
      throw StateError('$id was already sent to $relayUrl');
    }
    unawaited(
      _relayManager._sendRequestToRelay(_state, relayUrl, [
        for (final filter in filters) filter.clone(),
      ]),
    );
    return true;
  }

  /// The request may end once the relays it was sent to are done with it.
  /// Until then, it is held open for the relays still to come.
  void seal() {
    if (_sealed) return;
    _sealed = true;
    _relayManager._endPendingConnection(_state);
  }

  /// Sends a CLOSE to the relays still serving the request, then ends it.
  Future<void> close() => _closing ??= _relayManager._closeRequest(_state);
}
