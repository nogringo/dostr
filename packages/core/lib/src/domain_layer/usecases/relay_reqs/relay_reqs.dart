import 'dart:async';
import 'dart:collection';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../shared/logger/logger.dart';
import '../../../shared/nips/nip01/helpers.dart';
import '../../entities/relay_req_event.dart';
import '../../entities/relay_request_outcome.dart';
import '../relay_manager/relay_manager.dart';
import '../relay_manager/relay_manager_parts.dart';
import '../relay_manager/relay_requests.dart';
import '../relay_manager/request_state.dart';
import '../requests/verified_event_cache.dart';
import '../requests/verify_event.dart';

final _openReqs = Expando<Map<String, RelayReq>>();

/// The [RelayReq]s open on the manager behind [requests], by id
Map<String, RelayReq> _openOn(RelayRequests requests) =>
    _openReqs[requests] ??= {};

/// Opens [RelayReq]s: NIP-01 REQs on relays the caller picks.
///
/// No cache, no outbox routing, no merging of identical requests and no
/// pagination.
class RelayReqs {
  final RelayRequests _requests;
  final EventVerifier _eventVerifier;
  final VerifiedEventMemCache _verifiedEventCache = VerifiedEventMemCache();

  RelayReqs({
    required RelayManager relayManager,
    required EventVerifier eventVerifier,
  }) : _requests = relayManagerParts(relayManager).requests,
       _eventVerifier = eventVerifier;

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
    Map<RelayUrl, List<Filter>>? relays,
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
  late final Future<Map<RelayUrl, RelayRequestOutcome>> _done;
  final Set<RelayUrl> _sentTo = {};
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

    final deliveries = Queue<Future<void>>();
    Future<void> delivered = Future.value();
    _state.networkController.stream.listen(
      (received) {
        // starts once the event _maxVerifying places earlier is handed over,
        // so that at most that many are checked at once
        final slot = deliveries.length < _maxVerifying
            ? Future<void>.value()
            : deliveries.removeFirst();
        final verified = slot.then(
          (_) => _verify(received, eventVerifier, verifiedEventCache),
        );
        delivered = delivered.then((_) => verified).then((event) {
          if (event != null && !_events.isClosed) _events.add(event);
        });
        deliveries.add(delivered);
      },
      onDone: () => delivered.then((_) {
        unawaited(_events.close());
        _state.end();
        if (identical(inFlight[id], _state)) inFlight.remove(id);
        if (identical(open[id], this)) open.remove(id);
      }),
    );
  }

  static const _maxVerifying = 100;

  /// [received], or null when its id or signature is wrong, or its verifier
  /// failed.
  static Future<RelayReqEvent?> _verify(
    RelayReqEvent received,
    EventVerifier eventVerifier,
    VerifiedEventMemCache cache,
  ) async {
    try {
      final verified = await verifyEvent(
        received.event,
        eventVerifier: eventVerifier,
        cache: cache,
      );
      return verified == null ? null : received;
    } catch (error, stackTrace) {
      Logger.log.w(
        () => "Could not verify ${received.event.id}",
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// NIP-01 subscription id
  String get id => _state.id;

  bool get closeOnEose => _state.closeOnEose;

  /// Single-subscription: cancelling it closes the request, like [close].
  Stream<RelayReqEvent> get events => _events.stream;

  /// Where the request stands on each relay so far, keyed by relay url. A
  /// subscription shows [RelayRequestStatus.eose] on a relay that caught up.
  Map<RelayUrl, RelayRequestOutcome> get outcomes => _state.relayOutcomes;

  /// [outcomes] on every change, closed once the request is over.
  Stream<Map<RelayUrl, RelayRequestOutcome>> get outcomesStream =>
      _state.relayOutcomesStream;

  /// [outcomes] once every relay ended the request, on timeout, or on [close].
  Future<Map<RelayUrl, RelayRequestOutcome>> get done => _done;

  /// Whether the request ended on its timeout.
  bool get timedOut => _state.timedOut;

  /// Sends [filters] to [url] on the connection the request's
  /// [AuthPolicy] allows, and says whether it went out: nothing is sent once
  /// the request is over, nor twice to a relay.
  /// A filter that [Filter.matchesNothing] is left out, and a relay left with
  /// no filter is not sent to.
  ///
  /// A relay sent to after [seal] still has to answer before the request ends.
  bool send(RelayUrl url, List<Filter> filters) {
    final matchable = [
      for (final filter in filters)
        if (!filter.matchesNothing) filter.clone(),
    ];
    if (matchable.isEmpty ||
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
