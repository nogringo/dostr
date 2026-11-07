import 'dart:async';

import 'package:ndk_auth/ndk_auth.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'broadcast_response.dart';
import 'broadcast_exceptions.dart';
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
  final AuthAccounts _accounts;
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
    required AuthAccounts accounts,
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
    final signer = customSigner ?? _accounts.getLoggedAccount()?.signer;
    if (signer == null) {
      throw "cannot broadcast without a signer!";
    }
    return signer;
  }

  /// Sends [nostrEvent] to relays now. No queue enrollment, no retry. \
  /// [specificRelays] disables inbox/outbox (gossip) and broadcasts to the relays specified \
  /// [urlSet] where to broadcast instead, see [broadcastUrlSet] for the set used without either \
  /// [customSigner] if you want to use a different signer than the logged account of [AuthAccounts] \
  /// [considerDonePercent] the percentage (0.0, 1.0) of relays that need to accept the event for the broadcast to be considered done (overrides the default value) \
  /// [timeout] the timeout for the broadcast (overrides the default timeout) \
  /// [saveToCache] whether to save the event to cache (overrides the default value from config) \
  /// [auth] which identity this broadcast may be attributed to on relays (NIP-42), see [AuthPolicy] \
  /// [onUnavailable] called with the signed event and the parts of the set still unavailable, before it is sent \
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
    void Function(Nip01Event signed, List<UrlSet> unavailable)? onUnavailable,
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
        onUnavailable,
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
    void Function(Nip01Event signed, List<UrlSet> unavailable)? onUnavailable,
  ) async {
    final Nip01Event signed;
    final UrlSetResolution resolution;
    try {
      signed = signer == null
          ? publish.event
          : await signer.sign(publish.event);
      // resolved before the timeout starts, which is for the relays to answer
      resolution = await resolve(
        urlSet ?? broadcastUrlSet(signed, bootstrapRelays: _bootstrapRelays),
      );
      if (resolution.unavailable.isNotEmpty) {
        Logger.log.w(
          () =>
              'broadcast of ${signed.id} skips ${resolution.unavailableReasons}',
        );
        onUnavailable?.call(signed, resolution.unavailable);
      }
      publish.start(signed);
    } catch (error, stackTrace) {
      publish.fail(error, stackTrace);
      return;
    }
    try {
      for (final url in resolution.relays) {
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

  /// Resolves each part of the `union` [set] on its own, so one unreachable
  /// inbox does not hold back the others.
  Future<UrlSetResolution> resolve(UrlSet set) async {
    final parts = _parts(set).toList();
    final resolutions = await Future.wait([
      for (final part in parts) resolveUrlSet(part, _urlLists),
    ]);
    final relays = <String>[];
    final unavailable = <UrlSet>[];
    final reasons = <String>[];
    for (final (i, resolution) in resolutions.indexed) {
      switch (resolution) {
        case UrlsResolved(:final urls):
          relays.addAll(urls);
        case UrlsUnavailable(:final reason):
          unavailable.add(parts[i]);
          reasons.add(reason);
      }
    }
    return UrlSetResolution(
      relays: relays,
      unavailable: unavailable,
      unavailableReasons: reasons.join(', '),
    );
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

/// What [BroadcastSender.resolve] found for each part of a set.
class UrlSetResolution {
  /// The relays of the parts that resolved, in order, not deduplicated.
  final List<String> relays;

  /// The parts whose lists are still unavailable.
  final List<UrlSet> unavailable;

  final String unavailableReasons;

  const UrlSetResolution({
    required this.relays,
    required this.unavailable,
    required this.unavailableReasons,
  });
}
