part of '../relay_manager.dart';

/// Publishes signed events to relays the caller picks (NIP-01 EVENT).
///
/// This is the layer below `Broadcast`: no signing, no cache, no outbox
/// routing and no retry.
class RelayPublishes {
  final RelayManager _relayManager;

  RelayPublishes({required RelayManager relayManager})
    : _relayManager = relayManager;

  /// Sends [event], which must be signed, to each of [relays] and collects
  /// their OK, on the connections [auth] allows.
  ///
  /// It is done once every relay answered or failed, once [considerDonePercent]
  /// of them accepted the event, or after [timeout], not counting NIP-42
  /// authentication.
  NdkBroadcastResponse publish(
    Nip01Event event, {
    required Iterable<String> relays,
    AuthPolicy? auth,
    Duration timeout = BroadcastDefaults.TIMEOUT,
    double considerDonePercent = BroadcastDefaults.CONSIDER_DONE_PERCENT,
  }) {
    if (event.sig == null) {
      throw ArgumentError.value(event.id, 'event', 'must be signed');
    }
    final publish = open(
      event,
      auth: auth,
      timeout: timeout,
      considerDonePercent: considerDonePercent,
    )..start(event);
    relays.forEach(publish.send);
    publish.seal();
    return publish.response;
  }

  /// Opens the publish of [event], which may still have to be signed: it counts
  /// as in flight from now on. [RelayPublish.start] it with the signed event,
  /// then [RelayPublish.send] it to each relay and [RelayPublish.seal] it.
  ///
  /// [timeout] runs from [RelayPublish.start], see [publish].
  RelayPublish open(
    Nip01Event event, {
    AuthPolicy? auth,
    Duration timeout = BroadcastDefaults.TIMEOUT,
    double considerDonePercent = BroadcastDefaults.CONSIDER_DONE_PERCENT,
  }) => RelayPublish._(
    event,
    BroadcastState(
      timeout: timeout,
      considerDonePercent: considerDonePercent,
      auth: auth,
    ),
    _relayManager,
  );
}

/// One EVENT on the relays its caller picked, opened by [RelayPublishes.open].
class RelayPublish {
  /// the event as it was opened, signed or not
  final Nip01Event event;

  final BroadcastState _state;
  final RelayManager _relayManager;
  final Set<String> _sentTo = {};
  Nip01Event? _signed;

  /// The OK of each relay, as they come and once the publish is done.
  late final NdkBroadcastResponse response = NdkBroadcastResponse(
    publishEvent: event,
    broadcastDoneStream: _state.stateUpdates.map(
      (state) => state.broadcasts.values.toList(),
    ),
    broadcastDoneFuture: _state.publishDoneFuture.then(
      (state) => state.broadcasts.values.toList(),
    ),
  );

  RelayPublish._(this.event, this._state, this._relayManager) {
    _relayManager._trackBroadcast(event.id, _state);
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
    if (signed.id != event.id) _relayManager._trackBroadcast(signed.id, _state);
    _state.startTimeout();
  }

  /// Ends the publish on [error] instead, such as a signer that refused.
  void fail(Object error, [StackTrace? stackTrace]) =>
      _state.addError(error, stackTrace);

  /// Sends the signed event to [relayUrl] on the connection the publish's
  /// [AuthPolicy] allows, and says whether it went out: nothing is sent once
  /// the publish is over, nor twice to a relay.
  ///
  /// [connectTimeout] bounds the connecting, in seconds. [veto] is asked once
  /// the connection is up: a reason it gives not to send after all fails the
  /// relay with that reason.
  bool send(
    String relayUrl, {
    int connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT,
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
      _relayManager._publishToRelay(
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
