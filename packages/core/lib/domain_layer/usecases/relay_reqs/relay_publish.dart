import 'dart:async';

import '../../../config/broadcast_defaults.dart';
import '../../../config/relay_defaults.dart';
import 'package:dostr_url_set/dostr_url_set.dart';
import '../../../src/broadcast_state.dart';
import '../../../src/relay_broadcasts.dart';
import '../../../src/relay_manager_parts.dart';
import 'package:dostr_signer/dostr_signer.dart';
import '../../entities/broadcast_state.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import '../relay_manager.dart';

/// Publishes signed events to relays the caller picks (NIP-01 EVENT).
///
/// This is the layer below `Broadcast`: no signing, no cache, no outbox
/// routing and no retry.
class RelayPublishes {
  final RelayBroadcasts _broadcasts;

  RelayPublishes({required RelayManager relayManager})
    : _broadcasts = relayManagerParts(relayManager).broadcasts;

  /// Sends [event], which must be signed, to each of [relays] and collects
  /// their OK, on the connections [auth] allows.
  ///
  /// It is done once every relay answered or failed, once [considerDonePercent]
  /// of them accepted the event, or after [timeout], not counting NIP-42
  /// authentication.
  RelayPublish publish(
    Nip01Event event, {
    required Iterable<String> relays,
    AuthPolicy? auth,
    Duration timeout = BroadcastDefaults.timeout,
    double considerDonePercent = BroadcastDefaults.considerDonePercent,
  }) {
    if (event.sig == null) {
      throw ArgumentError.value(event.id, 'event', 'must be signed');
    }
    final relayPublish = open(
      event,
      auth: auth,
      timeout: timeout,
      considerDonePercent: considerDonePercent,
    )..start(event);
    relays.forEach(relayPublish.send);
    relayPublish.seal();
    return relayPublish;
  }

  /// Opens the publish of [event], which may still have to be signed: it counts
  /// as in flight from now on. [RelayPublish.start] it with the signed event,
  /// then [RelayPublish.send] it to each relay and [RelayPublish.seal] it.
  ///
  /// [timeout] runs from [RelayPublish.start], see [publish].
  RelayPublish open(
    Nip01Event event, {
    AuthPolicy? auth,
    Duration timeout = BroadcastDefaults.timeout,
    double considerDonePercent = BroadcastDefaults.considerDonePercent,
  }) => RelayPublish._(
    event,
    BroadcastState(
      timeout: timeout,
      considerDonePercent: considerDonePercent,
      auth: auth,
    ),
    _broadcasts,
  );
}

/// One EVENT on the relays its caller picked, opened by [RelayPublishes.open]
/// or [RelayPublishes.publish].
class RelayPublish {
  /// the event as it was opened, signed or not
  final Nip01Event event;

  final BroadcastState _state;
  final RelayBroadcasts _broadcasts;
  final Set<String> _sentTo = {};
  Nip01Event? _signed;

  /// The OK of each relay so far, keyed by relay url. A relay that did not
  /// answer yet has neither [RelayBroadcastResponse.okReceived] nor a
  /// [RelayBroadcastResponse.failure].
  Map<String, RelayBroadcastResponse> get outcomes => _outcomesOf(_state);

  /// [outcomes] each time a relay answers, closed once the publish is done.
  Stream<Map<String, RelayBroadcastResponse>> get outcomesStream =>
      _state.stateUpdates.map(_outcomesOf);

  /// [outcomes] once the publish is done, see [RelayPublishes.publish]. Fails
  /// with the error the publish was [fail]ed on.
  // late: an unawaited failure would otherwise surface as an uncaught error
  late final Future<Map<String, RelayBroadcastResponse>> done = _state
      .publishDoneFuture
      .then(_outcomesOf);

  static Map<String, RelayBroadcastResponse> _outcomesOf(
    BroadcastState state,
  ) => Map.unmodifiable(state.broadcasts);

  RelayPublish._(this.event, this._state, this._broadcasts) {
    _broadcasts.track(event.id, _state);
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
    if (signed.id != event.id) _broadcasts.track(signed.id, _state);
    _state.startTimeout();
  }

  /// Ends the publish on [error] instead, such as a signer that refused.
  void fail(Object error, [StackTrace? stackTrace]) =>
      _state.addError(error, stackTrace);

  /// Sends the signed event to [relayUrl] on the connection the publish's
  /// [AuthPolicy] allows, and says whether it went out: nothing is sent once
  /// the publish is over, nor twice to a relay.
  ///
  /// [connectTimeout] bounds the connecting. [veto] is asked once
  /// the connection is up: a reason it gives not to send after all fails the
  /// relay with that reason.
  bool send(
    String relayUrl, {
    Duration connectTimeout = defaultWebSocketConnectTimeout,
    Future<String?> Function()? veto,
  }) {
    final signed = _signed;
    if (signed == null) {
      throw StateError('${event.id} has to be started before it is sent');
    }
    final url = cleanRelayUrl(relayUrl);
    if (url == null || _state.networkController.isClosed || !_sentTo.add(url)) {
      return false;
    }
    unawaited(
      _broadcasts.publishToRelay(
        _state,
        url,
        signed,
        connectTimeout: connectTimeout,
        veto: veto,
      ),
    );
    return true;
  }

  /// The publish may end once the relays it was sent to answered. Without any,
  /// it ends right away.
  void seal() => _state.closeIfNoRelays();
}
