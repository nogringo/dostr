import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../config/publish_defaults.dart';
import '../../../config/relay_defaults.dart';
import '../../entities/relay_publish_outcome.dart';
import '../relay_manager/publish_state.dart';
import '../relay_manager/publishes_in_flight.dart';
import '../relay_manager/relay_manager.dart';
import '../relay_manager/relay_manager_parts.dart';

/// Publishes signed events to relays the caller picks (NIP-01 EVENT).
///
/// No signing, no cache, no outbox routing and no retry.
class RelayPublishes {
  final PublishesInFlight _publishes;

  RelayPublishes({required RelayManager relayManager})
    : _publishes = relayManagerParts(relayManager).publishes;

  /// Sends [event], which must be signed, to each of [relays] and collects
  /// their OK, on the connections [auth] allows.
  ///
  /// It is done once every relay answered or failed, once [considerDoneRatio]
  /// of them accepted the event, or after [timeout], not counting NIP-42
  /// authentication. [considerDoneRatio] is between 0 and 1.
  RelayPublish publish(
    Nip01Event event, {
    required Iterable<RelayUrl> relays,
    AuthPolicy? auth,
    Duration timeout = defaultPublishTimeout,
    double considerDoneRatio = defaultConsiderDoneRatio,
  }) {
    if (event.sig == null) {
      throw ArgumentError.value(event.id, 'event', 'must be signed');
    }
    final relayPublish = open(
      event,
      auth: auth,
      timeout: timeout,
      considerDoneRatio: considerDoneRatio,
    )..start(event);
    relays.forEach(relayPublish.send);
    relayPublish.seal();
    return relayPublish;
  }

  /// Opens the publish of [event], which may still have to be signed: it counts
  /// as in flight from now on. [RelayPublish.start] it with the signed event,
  /// then [RelayPublish.send] it to each relay and [RelayPublish.seal] it.
  ///
  /// [timeout] runs from [RelayPublish.start], see [publish]. Throws a
  /// [StateError] once the [RelayManager] was disposed.
  RelayPublish open(
    Nip01Event event, {
    AuthPolicy? auth,
    Duration timeout = defaultPublishTimeout,
    double considerDoneRatio = defaultConsiderDoneRatio,
  }) {
    if (_publishes.disposed) {
      throw StateError('the RelayManager was disposed');
    }
    if (!(considerDoneRatio >= 0 && considerDoneRatio <= 1)) {
      throw ArgumentError.value(
        considerDoneRatio,
        'considerDoneRatio',
        'must be between 0 and 1',
      );
    }
    return RelayPublish._(
      event,
      PublishState(
        timeout: timeout,
        considerDoneRatio: considerDoneRatio,
        auth: auth,
      ),
      _publishes,
    );
  }
}

/// One EVENT on the relays its caller picked, opened by [RelayPublishes.open]
/// or [RelayPublishes.publish].
class RelayPublish {
  /// the event as it was opened, signed or not
  final Nip01Event event;

  final PublishState _state;
  final PublishesInFlight _publishes;
  final Set<RelayUrl> _sentTo = {};
  Nip01Event? _signed;

  /// The OK of each relay so far, keyed by relay url. A relay that did not
  /// answer yet has neither [RelayPublishOutcome.okReceived] nor a
  /// [RelayPublishOutcome.failure].
  Map<RelayUrl, RelayPublishOutcome> get outcomes => _outcomesOf(_state);

  /// [outcomes] each time a relay answers, closed once the publish is done.
  Stream<Map<RelayUrl, RelayPublishOutcome>> get outcomesStream =>
      _state.stateUpdates.map(_outcomesOf);

  /// [outcomes] once the publish is done, see [RelayPublishes.publish]. Fails
  /// with the error the publish was [fail]ed on.
  // late: an unawaited failure would otherwise surface as an uncaught error
  late final Future<Map<RelayUrl, RelayPublishOutcome>> done = _state.done.then(
    _outcomesOf,
  );

  static Map<RelayUrl, RelayPublishOutcome> _outcomesOf(PublishState state) =>
      Map.unmodifiable(state.outcomes);

  RelayPublish._(this.event, this._state, this._publishes) {
    _publishes.track(event.id, _state);
  }

  /// Starts the publish with [signed], [event] once signed. The timeout runs
  /// from here.
  ///
  /// A remote signer may hand back an event it changed, under another id: the
  /// publish then answers to both.
  void start(Nip01Event signed) {
    if (_signed != null) {
      throw StateError('${event.id} was already started');
    }
    if (signed.sig == null) {
      throw ArgumentError.value(signed.id, 'signed', 'must be signed');
    }
    _signed = signed;
    if (signed.id != event.id) _publishes.track(signed.id, _state);
    _state.startTimeout();
  }

  /// Ends the publish on [error] instead, such as a signer that refused.
  void fail(Object error, [StackTrace? stackTrace]) =>
      _state.addError(error, stackTrace);

  /// Sends the signed event to [url] on the connection the publish's
  /// [AuthPolicy] allows, and says whether it went out: nothing is sent once
  /// the publish is over, nor twice to a relay.
  ///
  /// [connectTimeout] bounds the connecting.
  bool send(
    RelayUrl url, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
  }) {
    final signed = _signed;
    if (signed == null) {
      throw StateError('${event.id} has to be started before it is sent');
    }
    if (_state.isOver || !_sentTo.add(url)) {
      return false;
    }
    unawaited(
      _publishes.publishToRelay(
        _state,
        url,
        signed,
        connectTimeout: connectTimeout,
      ),
    );
    return true;
  }

  /// The publish may end once the relays it was sent to answered. Without any,
  /// it ends right away.
  void seal() => _state.closeIfNoRelays();
}
