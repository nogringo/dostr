// ignore_for_file: avoid_print

import 'dart:core';
import 'dart:math';

import 'package:ndk_core/config/bootstrap_relays.dart';
import 'package:ndk_core/config/broadcast_defaults.dart';
import 'package:ndk_core/shared/logger/logger.dart';
import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_response.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_state.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import '../entities/relay_set.dart';
import '../repositories/cache_manager.dart';
import 'package:ndk_core/domain_layer/repositories/event_signer.dart';
import 'engines/network_engine.dart';
import 'broadcast/obsolete_replaceable.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'user_relay_lists/user_relay_lists.dart';

class RelaySetsEngine implements NetworkEngine {
  static const Duration kDefaultStreamIdleTimeout = Duration(seconds: 5);

  final RelayManager _relayManager;

  final CacheManager _cacheManager;

  final List<String> _bootstrapRelays;

  /// engine that pre-calculates relay sets for gossip
  RelaySetsEngine({
    required RelayManager relayManager,
    required CacheManager cacheManager,
    required List<String>? bootstrapRelays,
  }) : _cacheManager = cacheManager,
       _relayManager = relayManager,
       _bootstrapRelays = bootstrapRelays ?? DEFAULT_BOOTSTRAP_RELAYS;

  @override
  Future<void> route(
    List<Filter> filters,
    RelaySend send, {
    RelaySet? relaySet,
    required int desiredCoverage,
  }) async {
    await _relayManager.seedRelaysConnected;

    final byRelay = <String, List<Filter>>{};
    void add(String url, List<Filter> relayFilters) => byRelay
        .putIfAbsent(cleanRelayUrl(url) ?? url, () => [])
        .addAll(relayFilters);
    void addToBootstrapRelays(Filter filter) {
      for (final url in cleanRelayUrls(_bootstrapRelays)) {
        add(url, RelaySet.sliceFilterAuthors(filter));
      }
    }

    for (final filter in filters) {
      if (relaySet == null) {
        addToBootstrapRelays(filter);
        continue;
      }
      final fromSet = relaySet.filtersByRelay(filter);
      Logger.log.d(
        () =>
            "request for ${filter.authors?.length ?? 0} authors with kinds: ${filter.kinds} made requests to ${fromSet.length} relays",
      );
      if (fromSet.isEmpty && relaySet.fallbackToBootstrapRelays) {
        Logger.log.d(
          () =>
              "making fallback requests to ${_bootstrapRelays.length} bootstrap relays",
        );
        addToBootstrapRelays(filter);
      }
      fromSet.forEach(add);
    }
    byRelay.forEach(send);
  }

  @override
  NdkBroadcastResponse handleEventBroadcast({
    required Nip01Event nostrEvent,
    required EventSigner? signer,
    required BroadcastState broadcastState,
  }) {
    Future<void> asyncStuff() async {
      final Nip01Event workingEvent;

      try {
        if (signer != null) {
          workingEvent = await signer.sign(nostrEvent);
        } else {
          workingEvent = nostrEvent;
        }
      } catch (e, stackTrace) {
        broadcastState.addError(e, stackTrace);
        return;
      }
      broadcastState.startTimeout();

      // =====================================================================================
      // own outbox
      // =====================================================================================
      // TODO should not only depend on cached, but go fetch it if not present in cache
      final nip65List = (await UserRelayLists.getUserRelayListCacheLatest(
        pubkeys: [workingEvent.pubKey],
        cacheManager: _cacheManager,
      ));
      // make a copy of the keys since connectRelay may mutate the underlying map
      // several connections can share a url, and broadcasting twice to the
      // same relay would duplicate the event
      List<String> writeRelaysUrls = _relayManager.globalState.relays.keys
          .map((key) => key.url)
          .toSet()
          .toList();
      if (nip65List.isNotEmpty) {
        writeRelaysUrls = nip65List.first.relays.entries
            .where((element) => element.value.isWrite)
            .map((e) => e.key)
            .toList();
      } else {
        Logger.log.w(
          () =>
              "could not find user relay list from nip65, using default bootstrap relays",
        );
      }
      final relayUrls = [...writeRelaysUrls];

      // =====================================================================================
      // other inbox
      // =====================================================================================
      if (workingEvent.pTags.isNotEmpty) {
        final nip65Data = await UserRelayLists.getUserRelayListCacheLatest(
          pubkeys: workingEvent.pTags,
          cacheManager: _cacheManager,
        );

        /// filter read relays
        for (final userNip65 in nip65Data) {
          final completeList = userNip65.relays.entries
              .where((element) => element.value.isRead)
              .map((e) => e.key)
              .toList();

          // cut list of at a certain threshold
          relayUrls.addAll(
            completeList.sublist(
              0,
              min(
                completeList.length,
                BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST,
              ),
            ),
          );
        }
      }

      // a relay in an outbox and an inbox gets the event once
      await Future.wait([
        for (final url in cleanRelayUrls(relayUrls).toSet())
          _relayManager.publishToRelay(
            broadcastState,
            url,
            workingEvent,
            connectTimeout: 1,
            veto: () => obsoleteReplaceableVeto(_cacheManager, workingEvent),
          ),
      ]);
      broadcastState.closeIfNoRelays();
    }

    asyncStuff();

    return NdkBroadcastResponse.fromState(nostrEvent, broadcastState);
  }
}
