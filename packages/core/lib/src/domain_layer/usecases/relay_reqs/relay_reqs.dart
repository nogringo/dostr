import 'dart:async';

import 'package:rxdart/rxdart.dart';

import 'package:dostr_url_set/dostr_url_set.dart';
import '../../../shared/nips/nip01/helpers.dart';
import '../relay_manager/relay_manager_parts.dart';
import '../relay_manager/relay_requests.dart';
import '../relay_manager/request_state.dart';
import 'package:dostr_signer/dostr_signer.dart';
import '../../entities/relay_req_event.dart';
import '../../entities/relay_request_outcome.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import '../relay_manager/relay_manager.dart';
import '../requests/verified_event_cache.dart';
import '../requests/verify_event_stream.dart';

final _openReqs = Expando<Map<String, RelayReq>>();

/// The [RelayReq]s open on the manager behind [requests], by id
Map<String, RelayReq> _openOn(RelayRequests requests) =>
    _openReqs[requests] ??= {};

/// Opens [RelayReq]s: NIP-01 REQs on relays the caller picks.
///
/// This is the layer below `Requests`: no cache, no outbox routing, no merging
/// of identical requests and no pagination.
class RelayReqs {
  final RelayRequests _requests;
  final EventVerifier _eventVerifier;
  final VerifiedEventMemCache _verifiedEventCache;

  RelayReqs({
    required RelayManager relayManager,
    required EventVerifier eventVerifier,
    VerifiedEventMemCache? verifiedEventCache,
  }) : _requests = relayManagerParts(relayManager).requests,
       _eventVerifier = eventVerifier,
       _verifiedEventCache = verifiedEventCache ?? VerifiedEventMemCache();

  /// Forgets which signatures were already checked.
  void clearVerifiedEventCache() => _verifiedEventCache.clear();

  /// The ids of the REQs open on this manager, whatever [RelayReqs] opened
  /// them.
  List<String> get openIds => _openOn(_requests).keys.toList();

  /// Closes the REQ open under [id] on this manager, whatever [RelayReqs]
  /// opened it, like [RelayReq.close]. Says whether there was one.
  Future<bool> close(String id) async {
    final req = _openOn(_requests)[id];
    if (req == null) return false;
    await req.close();
    return true;
  }

  /// Closes every REQ open on this manager, whatever [RelayReqs] opened them.
  Future<void> closeAll() async {
    await Future.wait([
      for (final req in _openOn(_requests).values.toList()) req.close(),
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
    if (_requests.inFlight.containsKey(reqId)) {
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
      requests: _requests,
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
/// [events] are verified, each with the relay that sent it. They are not
/// deduplicated: an event two relays hold arrives twice.
class RelayReq {
  final RequestState _state;
  final RelayRequests _requests;
  late final StreamController<RelayReqEvent> _events = StreamController(
    onCancel: close,
  );
  late final Future<Map<String, RelayRequestOutcome>> _done;
  final Set<String> _sentTo = {};
  bool _sealed = false;
  Future<void>? _closing;

  RelayReq._(
    this._state, {
    required RelayRequests requests,
    required EventVerifier eventVerifier,
    required VerifiedEventMemCache verifiedEventCache,
  }) : _requests = requests {
    final inFlight = requests.inFlight;
    final open = _openOn(requests);
    _state.onTimeout = (_) => close();
    // released by seal: until then, more relays may come
    requests.beginPendingConnection(_state);
    inFlight[id] = _state;
    open[id] = this;
    _done = _state.ended.then((_) => _state.relayOutcomes);

    _state.networkController.stream
        .flatMap(
          (received) => Stream.fromFuture(
            verifyEvent(
              received.event,
              eventVerifier: eventVerifier,
              cache: verifiedEventCache,
            ).then(
              (verified) => verified == null
                  ? null
                  : RelayReqEvent(verified, received.relayUrl),
            ),
          ),
          maxConcurrent: 100,
        )
        .whereType<RelayReqEvent>()
        .listen(
          (event) {
            if (!_events.isClosed) _events.add(event);
          },
          onDone: () {
            unawaited(_events.close());
            _state.end();
            if (identical(inFlight[id], _state)) inFlight.remove(id);
            if (identical(open[id], this)) open.remove(id);
          },
        );
  }

  /// NIP-01 subscription id
  String get id => _state.id;

  bool get closeOnEose => _state.closeOnEose;

  /// Single-subscription: cancelling it closes the request, like [close].
  Stream<RelayReqEvent> get events => _events.stream;

  /// Where the request stands on each relay so far, keyed by relay url. A
  /// subscription shows [RelayRequestStatus.eose] on a relay that caught up.
  Map<String, RelayRequestOutcome> get outcomes => _state.relayOutcomes;

  /// [outcomes] on every change, closed once the request is over.
  Stream<Map<String, RelayRequestOutcome>> get outcomesStream =>
      _state.relayOutcomesStream;

  /// [outcomes] once every relay ended the request, on timeout, or on [close].
  Future<Map<String, RelayRequestOutcome>> get done => _done;

  /// Whether the request ended on its timeout.
  bool get timedOut => _state.timedOut;

  /// Sends [filters] to [relayUrl] on the connection the request's
  /// [AuthPolicy] allows, and says whether it went out: nothing is sent once
  /// the request is over, to a url that is not a relay's, nor twice to a relay.
  /// A filter that [Filter.matchesNothing] is left out, and a relay left with
  /// no filter is not sent to.
  ///
  /// A relay sent to after [seal] still has to answer before the request ends.
  bool send(String relayUrl, List<Filter> filters) {
    final url = cleanRelayUrl(relayUrl);
    final matchable = [
      for (final filter in filters)
        if (!filter.matchesNothing) filter.clone(),
    ];
    if (url == null ||
        matchable.isEmpty ||
        !_requests.isStillInFlight(_state) ||
        _state.networkController.isClosed ||
        !_sentTo.add(url)) {
      return false;
    }
    unawaited(_requests.sendToRelay(_state, url, matchable));
    return true;
  }

  /// The request may end once the relays it was sent to are done with it.
  /// Until then, it is held open for the relays still to come.
  void seal() {
    if (_sealed) return;
    _sealed = true;
    _requests.endPendingConnection(_state);
  }

  /// Sends a CLOSE to the relays still serving the request, then ends it.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await _requests.close(_state);
    final open = _openOn(_requests);
    if (identical(open[id], this)) open.remove(id);
  }
}
