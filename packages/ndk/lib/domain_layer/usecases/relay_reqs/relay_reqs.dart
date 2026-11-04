import 'dart:async';

import '../../../shared/nips/nip01/helpers.dart';
import '../../entities/auth_policy.dart';
import '../../entities/filter.dart';
import '../../entities/ndk_request.dart';
import '../../entities/nip_01_event.dart';
import '../../entities/relay_connection_key.dart';
import '../../entities/relay_request_outcome.dart';
import '../../entities/request_state.dart';
import '../../repositories/event_verifier.dart';
import '../relay_manager.dart';
import '../requests/verified_event_cache.dart';
import '../requests/verify_event_stream.dart';

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

  /// Opens a REQ.
  ///
  /// With [relays], each of them gets its filters and the request is sealed
  /// right away. Without, add relays with [RelayReq.send], then
  /// [RelayReq.seal].
  ///
  /// [closeOnEose] makes it a query, ended once every relay sent its EOSE.
  /// Otherwise it is a subscription, which lives until [RelayReq.close].
  /// [timeout] ends it after that long, not counting NIP-42 authentication.
  RelayReq req({
    Map<String, List<Filter>>? relays,
    String? id,
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
      RequestState(_ndkRequest(reqId, closeOnEose, auth, timeout)),
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

  static NdkRequest _ndkRequest(
    String id,
    bool closeOnEose,
    AuthPolicy? auth,
    Duration? timeout,
  ) {
    final request = closeOnEose
        ? NdkRequest.query(
            id,
            filters: [],
            timeoutDuration: timeout,
            auth: auth,
            cacheRead: false,
            cacheWrite: false,
          )
        : NdkRequest.subscription(
            id,
            filters: [],
            auth: auth,
            cacheRead: false,
            cacheWrite: false,
          );
    // NdkRequest.subscription takes no timeout
    return request..timeoutDuration = timeout;
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
    _state.onTimeout = (_) => close();
    // RequestState.close awaits it, which only completes once listened to
    unawaited(_state.cacheController.stream.drain<void>());
    unawaited(_state.cacheController.close());
    // released by seal: until then, more relays may come
    relayManager.beginPendingConnection(_state);
    inFlight[id] = _state;
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
      },
    );
  }

  /// NIP-01 subscription id
  String get id => _state.id;

  bool get closeOnEose => _state.request.closeOnEOSE;

  /// Single-subscription: cancelling it closes the request, like [close].
  Stream<Nip01Event> get events => _events.stream;

  /// What the request ended with on each relay so far, keyed by relay url.
  Map<String, RelayRequestOutcome> get outcomes => _state.relayOutcomes;

  /// [outcomes] on every change, closed once the request is over.
  Stream<Map<String, RelayRequestOutcome>> get outcomesStream =>
      _state.relayOutcomesStream;

  /// [outcomes] once every relay ended the request, on timeout, or on [close].
  Future<Map<String, RelayRequestOutcome>> get done => _done;

  /// Sends [filters] to [relayUrl] on the connection the request's
  /// [AuthPolicy] allows. One call per relay, before [seal].
  void send(String relayUrl, List<Filter> filters) {
    if (_sealed) {
      throw StateError('$id is sealed, no relay can be added');
    }
    if (!_sentTo.add(RelayConnectionKey.anonymous(relayUrl).url)) {
      throw StateError('$id was already sent to $relayUrl');
    }
    if (!_relayManager.isStillInFlight(_state)) return;
    unawaited(
      _relayManager.sendRequestToRelay(_state, relayUrl, [
        for (final filter in filters) filter.clone(),
      ]),
    );
  }

  /// No relay will be added anymore: the request ends once the relays it was
  /// sent to are done with it.
  void seal() {
    if (_sealed) return;
    _sealed = true;
    _relayManager.endPendingConnection(_state);
  }

  /// Sends a CLOSE to the relays still serving the request, then ends it.
  Future<void> close() => _closing ??= _relayManager.closeRequest(_state);
}
