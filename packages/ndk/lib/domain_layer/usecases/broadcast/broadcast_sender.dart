import 'dart:async';

import 'package:ndk/ndk.dart';

import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'broadcast_url_set.dart';
import 'obsolete_replaceable.dart';

/// Low-level broadcaster that sends events to relays immediately. \
/// Has no queue, retry, or persistence logic. \
/// Both the public [Broadcast] facade and [PendingBroadcastDelivery] retry path
/// delegate here so the retry path never re-enters queue enrollment.
class BroadcastSender {
  final UrlListFn _urlLists;
  final List<String> _bootstrapRelays;
  final RelayManager _relayManager;
  final RelayPublishes _relayPublishes;
  final Accounts _accounts;
  final CacheManager _cacheManager;
  final double _considerDonePercent;
  final Duration _timeout;
  final bool _saveToCache;

  BroadcastSender({
    required CacheManager cacheManager,
    required UrlListFn urlLists,
    required List<String> bootstrapRelays,
    required RelayManager relayManager,
    RelayPublishes? relayPublishes,
    required Accounts accounts,
    required double considerDonePercent,
    required Duration timeout,
    required bool saveToCache,
  }) : _accounts = accounts,
       _cacheManager = cacheManager,
       _urlLists = urlLists,
       _bootstrapRelays = bootstrapRelays,
       _relayManager = relayManager,
       _relayPublishes =
           relayPublishes ?? RelayPublishes(relayManager: relayManager),
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
  /// [urlSet] where to broadcast instead, see [broadcastUrlSet] for the set used without either \
  /// [customSigner] if you want to use a different signer than the one from currently logged in user in [Accounts] \
  /// [considerDonePercent] the percentage (0.0, 1.0) of relays that need to accept the event for the broadcast to be considered done (overrides the default value) \
  /// [timeout] the timeout for the broadcast (overrides the default timeout) \
  /// [saveToCache] whether to save the event to cache (overrides the default value from config) \
  /// [auth] which identity this broadcast may be attributed to on relays (NIP-42), see [AuthPolicy] \
  /// [returns] a [NdkBroadcastResponse] object containing the result => success per relay
  NdkBroadcastResponse broadcast({
    required Nip01Event nostrEvent,
    Iterable<String>? specificRelays,
    UrlSet? urlSet,
    EventSigner? customSigner,
    double? considerDonePercent,
    Duration? timeout,
    bool? saveToCache,
    AuthPolicy? auth,
  }) {
    if (specificRelays != null && urlSet != null) {
      throw ArgumentError('pass specificRelays or urlSet, not both');
    }
    final myConsiderDonePercent = considerDonePercent ?? _considerDonePercent;
    final myTimeout = timeout ?? _timeout;
    final mySaveToCache = saveToCache ?? _saveToCache;

    if (auth is AuthPolicyRequire && !auth.account.signer.canSign()) {
      throw BroadcastAuthUnavailableException(auth.account.pubkey);
    }

    final signer = nostrEvent.sig == null
        ? _checkSinger(customSigner: customSigner)
        : null;

    final publish = _relayPublishes.open(
      nostrEvent,
      auth: auth,
      timeout: myTimeout,
      considerDonePercent: myConsiderDonePercent,
    );

    if (mySaveToCache) {
      _cacheManager.saveEvent(nostrEvent);
    }

    unawaited(
      _send(
        publish,
        signer,
        specificRelays == null
            ? urlSet
            : UrlSet.explicit(cleanRelayUrls(specificRelays.toList())),
      ),
    );
    return NdkBroadcastResponse(
      publishEvent: publish.event,
      broadcastDoneStream: publish.outcomesStream.map(
        (outcomes) => outcomes.values.toList(),
      ),
      broadcastDoneFuture: publish.done.then(
        (outcomes) => outcomes.values.toList(),
      ),
    );
  }

  Future<void> _send(
    RelayPublish publish,
    EventSigner? signer,
    UrlSet? urlSet,
  ) async {
    final Nip01Event signed;
    final List<String> relays;
    try {
      signed = signer == null
          ? publish.event
          : await signer.sign(publish.event);
      // resolved before the timeout starts, which is for the relays to answer
      relays = await _resolve(
        urlSet ?? broadcastUrlSet(signed, bootstrapRelays: _bootstrapRelays),
        signed,
      );
      publish.start(signed);
    } catch (error, stackTrace) {
      publish.fail(error, stackTrace);
      return;
    }
    try {
      for (final url in relays) {
        publish.send(
          url,
          connectTimeout: const Duration(seconds: 1),
          veto: () => obsoleteReplaceableVeto(_cacheManager, signed),
        );
      }
    } finally {
      publish.seal();
    }
  }

  /// The relays of each part of [set] that resolved. A part still unavailable
  /// is skipped, so one unreachable inbox does not hold back the others.
  Future<List<String>> _resolve(UrlSet set, Nip01Event event) async {
    final resolutions = await Future.wait([
      for (final part in _parts(set)) resolveUrlSet(part, _urlLists),
    ]);
    final relays = <String>[];
    for (final resolution in resolutions) {
      switch (resolution) {
        case UrlsResolved(:final urls):
          relays.addAll(urls);
        case UrlsUnavailable(:final reason):
          Logger.log.w(() => 'broadcast of ${event.id} skips $reason');
      }
    }
    return relays;
  }

  static Iterable<UrlSet> _parts(UrlSet set) sync* {
    if (set is UnionUrls) {
      for (final part in set.sets) {
        yield* _parts(part);
      }
    } else {
      yield set;
    }
  }
}
