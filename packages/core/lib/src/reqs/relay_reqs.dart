import 'dart:async';
import 'dart:collection';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../config/request_defaults.dart';
import '../helpers/logger.dart';
import '../helpers/secure_random_hex.dart';
import '../relay_manager.dart';
import '../relay_manager_parts.dart';
import 'relay_req_event.dart';
import 'relay_request_outcome.dart';
import 'relay_requests.dart';
import 'request_state.dart';
import 'verified_event_cache.dart';
import 'verify_event.dart';

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
  /// Each of [relays] gets its filters in a single REQ, on the connection that
  /// [auth] allows. A filter that [Filter.matchesNothing] is left out, and a
  /// relay left with no filter gets nothing.
  ///
  /// With [closeOnEose], the REQ is a query: it ends once every relay sent its
  /// EOSE. Otherwise it is a subscription, which lives until [RelayReq.close].
  ///
  /// [timeout] ends the REQ after that long. Time spent on NIP-42
  /// authentication does not count. A query gets [defaultQueryTimeout] by
  /// default, a subscription no timeout. [name] only shows in logs.
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

    final state = RequestState(
      reqId,
      name: name,
      closeOnEose: closeOnEose,
      auth: auth,
      timeoutDuration: timeout ?? (closeOnEose ? defaultQueryTimeout : null),
    );
    final req = RelayReq._(
      state,
      requests: _requests,
      eventVerifier: _eventVerifier,
      verifiedEventCache: _verifiedEventCache,
    );
    try {
      _requests.start(state, {
        for (final MapEntry(key: url, value: filters) in relays.entries)
          if (_matchable(filters) case final matchable
              when matchable.isNotEmpty)
            url: matchable,
      });
    } catch (_) {
      unawaited(req.close());
      rethrow;
    }
    return req;
  }

  static List<Filter> _matchable(List<Filter> filters) => [
    for (final filter in filters)
      if (!filter.matchesNothing) filter.clone(),
  ];
}

/// One REQ on the relays its caller picked, opened by [RelayReqs.req].
///
/// [events] are verified, each with the relay that sent it. They are not
/// deduplicated: an event that two relays hold arrives twice.
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
    _done = _state.ended.then((_) => _state.relayOutcomes);

    final deliveries = Queue<Future<void>>();
    Future<void> delivered = Future.value();
    _state.received.listen(
      (received) {
        // waits for the event _maxVerifying places earlier to be handed over,
        // so at most that many are checked at once
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

  /// The NIP-01 subscription id.
  String get id => _state.id;

  /// The verified events, in the order each relay sent them.
  ///
  /// It is a single-subscription stream: cancelling it closes the request, as
  /// [close] does. It keeps every event until it is listened to, without a
  /// limit, so listen to a subscription right away or close it.
  Stream<RelayReqEvent> get events => _events.stream;

  /// Where the request stands on each relay so far, keyed by relay url. A
  /// subscription shows [RelayRequestStatus.eose] on a relay that caught up.
  Map<RelayUrl, RelayRequestOutcome> get outcomes => _state.relayOutcomes;

  /// [outcomes] on every change, closed once the request is over.
  Stream<Map<RelayUrl, RelayRequestOutcome>> get outcomesStream =>
      _state.relayOutcomesStream;

  /// [outcomes] once every relay ended the request, on timeout, or on [close].
  Future<Map<RelayUrl, RelayRequestOutcome>> get done => _done;

  /// Sends a CLOSE to the relays still serving the request, then ends it.
  ///
  /// A relay that had yet to end it reports [RelayRequestStatus.cancelled], or
  /// [RelayRequestStatus.eose] for a subscription that caught up there.
  Future<void> close() => _closing ??= _requests.close(_state);
}
