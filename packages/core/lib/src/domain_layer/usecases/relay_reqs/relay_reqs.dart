import 'dart:async';
import 'dart:collection';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../config/request_defaults.dart';
import '../../../shared/helpers/secure_random_hex.dart';
import '../../../shared/logger.dart';
import '../../entities/relay_req_event.dart';
import '../../entities/relay_request_outcome.dart';
import '../relay_manager/relay_manager.dart';
import '../relay_manager/relay_manager_parts.dart';
import '../relay_manager/relay_requests.dart';
import '../relay_manager/request_state.dart';
import '../requests/verified_event_cache.dart';
import '../requests/verify_event.dart';

/// Opens [RelayReq]s: NIP-01 REQs on relays the caller picks.
///
/// No cache, no outbox routing, no merging of identical requests and no
/// pagination.
final class RelayReqs {
  final RelayRequests _requests;
  final EventVerifier _eventVerifier;
  final VerifiedEventMemCache _verifiedEventCache = VerifiedEventMemCache();

  RelayReqs({
    required RelayManager relayManager,
    required EventVerifier eventVerifier,
  }) : _requests = relayManagerParts(relayManager).requests,
       _eventVerifier = eventVerifier;

  /// Opens a REQ. Throws a [StateError] once the [RelayManager] was disposed.
  ///
  /// Each of [relays] gets its filters in a single REQ, on the connection
  /// [auth] allows. A filter that [Filter.matchesNothing] is left out, and a
  /// relay left with no filter is not sent to.
  ///
  /// [closeOnEose] makes it a query, ended once every relay sent its EOSE.
  /// Otherwise it is a subscription, which lives until [RelayReq.close].
  /// [timeout] ends it after that long, not counting NIP-42 authentication:
  /// [defaultQueryTimeout] for a query by default, never for a subscription.
  /// [name] only shows in logs.
  RelayReq req({
    required Map<RelayUrl, List<Filter>> relays,
    String? id,
    String? name,
    bool closeOnEose = true,
    AuthPolicy? auth,
    Duration? timeout,
  }) {
    if (_requests.disposed) {
      throw StateError('the RelayManager was disposed');
    }
    final reqId = id ?? secureRandomHex(16);
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
        timeoutDuration: timeout ?? (closeOnEose ? defaultQueryTimeout : null),
      ),
      requests: _requests,
      eventVerifier: _eventVerifier,
      verifiedEventCache: _verifiedEventCache,
    );
    try {
      relays.forEach(req._send);
    } catch (_) {
      unawaited(req.close());
      rethrow;
    }
    _requests.endPendingConnection(req._state);
    return req;
  }
}

/// One REQ on the relays its caller picked, opened by [RelayReqs.req].
///
/// [events] are verified, each with the relay that sent it. They are not
/// deduplicated: an event two relays hold arrives twice.
final class RelayReq {
  final RequestState _state;
  final RelayRequests _requests;
  late final StreamController<RelayReqEvent> _events = StreamController(
    onCancel: close,
  );
  late final Future<Map<RelayUrl, RelayRequestOutcome>> _done;
  Future<void>? _closing;

  RelayReq._(
    this._state, {
    required RelayRequests requests,
    required EventVerifier eventVerifier,
    required VerifiedEventMemCache verifiedEventCache,
  }) : _requests = requests {
    final inFlight = requests.inFlight;
    _state.onTimeout = (_) => close();
    // released once every relay was handed its filters
    requests.beginPendingConnection(_state);
    inFlight[id] = _state;
    _done = _state.ended.then((_) => _state.relayOutcomes);

    final deliveries = Queue<Future<void>>();
    Future<void> delivered = Future.value();
    _state.received.listen(
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
      logger.warning(
        () => "Could not verify ${received.event.id}",
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// NIP-01 subscription id
  String get id => _state.id;

  /// Single-subscription: cancelling it closes the request, like [close].
  ///
  /// It keeps every event until it is listened to, without a limit: listen to
  /// a subscription right away, or close it.
  Stream<RelayReqEvent> get events => _events.stream;

  /// Where the request stands on each relay so far, keyed by relay url. A
  /// subscription shows [RelayRequestStatus.eose] on a relay that caught up.
  Map<RelayUrl, RelayRequestOutcome> get outcomes => _state.relayOutcomes;

  /// [outcomes] on every change, closed once the request is over.
  Stream<Map<RelayUrl, RelayRequestOutcome>> get outcomesStream =>
      _state.relayOutcomesStream;

  /// [outcomes] once every relay ended the request, on timeout, or on [close].
  Future<Map<RelayUrl, RelayRequestOutcome>> get done => _done;

  void _send(RelayUrl url, List<Filter> filters) {
    final matchable = [
      for (final filter in filters)
        if (!filter.matchesNothing) filter.clone(),
    ];
    if (matchable.isEmpty) return;
    unawaited(_requests.sendToRelay(_state, url, matchable));
  }

  /// Sends a CLOSE to the relays still serving the request, then ends it. A
  /// relay that had yet to end it reports [RelayRequestStatus.cancelled], or
  /// [RelayRequestStatus.eose] for a subscription that caught up there.
  Future<void> close() => _closing ??= _requests.close(_state);
}
