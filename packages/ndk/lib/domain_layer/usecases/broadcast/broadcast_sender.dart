import 'dart:async';

import 'package:ndk/ndk.dart';

import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_state.dart';
import '../engines/network_engine.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'obsolete_replaceable.dart';

/// Low-level broadcaster that sends events to relays immediately. \
/// Has no queue, retry, or persistence logic. \
/// Both the public [Broadcast] facade and [PendingBroadcastDelivery] retry path
/// delegate here so the retry path never re-enters queue enrollment.
class BroadcastSender {
  final NetworkEngine _engine;
  final RelayManager _relayManager;
  final Accounts _accounts;
  final CacheManager _cacheManager;
  final double _considerDonePercent;
  final Duration _timeout;
  final bool _saveToCache;

  BroadcastSender({
    required CacheManager cacheManager,
    required NetworkEngine networkEngine,
    required RelayManager relayManager,
    required Accounts accounts,
    required double considerDonePercent,
    required Duration timeout,
    required bool saveToCache,
  }) : _accounts = accounts,
       _cacheManager = cacheManager,
       _engine = networkEngine,
       _relayManager = relayManager,
       _considerDonePercent = considerDonePercent,
       _timeout = timeout,
       _saveToCache = saveToCache;

  bool isEventInFlight(String eventId) => _relayManager.isBroadcasting(eventId);

  /// [throws] if the default signer and the custom signer are null \
  /// [returns] the signer that is not null, if both are provided returns [customSigner]
  EventSigner _checkSinger({EventSigner? customSigner}) {
    if (_accounts.isNotLoggedIn && customSigner == null) {
      throw "cannot broadcast without a signer!";
    }
    return customSigner ?? _accounts.getLoggedAccount()!.signer;
  }

  /// Sends [nostrEvent] to relays now. No queue enrollment, no retry. \
  /// [specificRelays] disables inbox/outbox (gossip) and broadcasts to the relays specified \
  /// [customSigner] if you want to use a different signer than the one from currently logged in user in [Accounts] \
  /// [considerDonePercent] the percentage (0.0, 1.0) of relays that need to respond with "OK" for the broadcast to be considered done (overrides the default value) \
  /// [timeout] the timeout for the broadcast (overrides the default timeout) \
  /// [saveToCache] whether to save the event to cache (overrides the default value from config) \
  /// [auth] which identity this broadcast may be attributed to on relays (NIP-42), see [AuthPolicy] \
  /// [returns] a [NdkBroadcastResponse] object containing the result => success per relay
  NdkBroadcastResponse broadcast({
    required Nip01Event nostrEvent,
    Iterable<String>? specificRelays,
    EventSigner? customSigner,
    double? considerDonePercent,
    Duration? timeout,
    bool? saveToCache,
    AuthPolicy? auth,
  }) {
    final myConsiderDonePercent = considerDonePercent ?? _considerDonePercent;
    final myTimeout = timeout ?? _timeout;
    final mySaveToCache = saveToCache ?? _saveToCache;

    if (auth is AuthPolicyRequire && !auth.account.signer.canSign()) {
      throw BroadcastAuthUnavailableException(auth.account.pubkey);
    }

    final signer = nostrEvent.sig == null
        ? _checkSinger(customSigner: customSigner)
        : null;

    final broadcastState = BroadcastState(
      considerDonePercent: myConsiderDonePercent,
      timeout: myTimeout,
      auth: auth,
    );
    _relayManager.trackBroadcast(nostrEvent, broadcastState);

    if (mySaveToCache) {
      _cacheManager.saveEvent(nostrEvent);
    }

    if (specificRelays != null) {
      unawaited(
        _sendToSpecificRelays(
          nostrEvent,
          signer,
          broadcastState,
          cleanRelayUrls(specificRelays.toList()).toSet(),
        ),
      );
      return NdkBroadcastResponse.fromState(nostrEvent, broadcastState);
    }

    return _engine.handleEventBroadcast(
      nostrEvent: nostrEvent,
      signer: signer,
      broadcastState: broadcastState,
    );
  }

  /// Specific relays bypass outbox routing, so no engine is involved.
  Future<void> _sendToSpecificRelays(
    Nip01Event nostrEvent,
    EventSigner? signer,
    BroadcastState broadcastState,
    Set<String> relays,
  ) async {
    final Nip01Event signed;
    try {
      signed = signer == null ? nostrEvent : await signer.sign(nostrEvent);
    } catch (error, stackTrace) {
      broadcastState.addError(error, stackTrace);
      return;
    }
    broadcastState.startTimeout();
    await Future.wait([
      for (final url in relays)
        _relayManager.publishToRelay(
          broadcastState,
          url,
          signed,
          connectTimeout: 1,
          veto: () => obsoleteReplaceableVeto(_cacheManager, signed),
        ),
    ]);
    broadcastState.closeIfNoRelays();
  }
}
