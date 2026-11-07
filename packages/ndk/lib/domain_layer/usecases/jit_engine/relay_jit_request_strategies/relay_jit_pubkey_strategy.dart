import 'dart:async';

import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk/shared/nips/nip65/relay_ranking.dart';
import 'package:ndk/domain_layer/usecases/jit_engine/jit_engine.dart';
import 'package:ndk/domain_layer/usecases/jit_engine/relay_jit_request_strategies/relay_jit_blast_all_strategy.dart';

import '../../../entities/jit_engine_relay_connectivity_data.dart';
import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import '../../user_relay_lists/user_relay_lists.dart';
import '../jit_request_plan.dart';

/// Strategy Description:
///
/// 1.) look for connected relays that cover the pubkey, and give each the
/// pubkeys it covers; decrease desiredCoverage for pubkey
///
/// 2.) for not covered pubkeys look for relays in nip65 data, while boosting
/// already connected relays
///
/// 3.) case=> if no relay is found, blast the request to all connected
/// bootstrap relays
///
/// 4.) case=> good relay found but not connected yet: connect, then send out
/// the request, see [RelayJitPubkeyStrategy.connectCandidates]
///

/// A relay picked for some pubkeys of a filter, that has yet to be connected.
class JitRelayCandidate {
  final String url;
  final Filter filter;
  final List<String> pubkeys;
  final ReadWriteMarker direction;

  JitRelayCandidate(this.url, this.filter, this.pubkeys, this.direction);
}

class RelayJitPubkeyStrategy with Logger {
  /// Adds [filter] to [plan] for the connected relays that cover its pubkeys,
  /// and returns the relays still to connect to.
  static Future<List<JitRelayCandidate>> plan({
    required JitRequestPlan plan,

    // specific filter (only one for this request)
    required Filter filter,
    required List<RelayConnectivity> connectedRelays,
    required List<String> bootstrapRelays,

    /// used to get the nip65 data if its necessary to look for not covered pubkeys
    required CacheManager cacheManager,
    required int desiredCoverage,
    required ReadWriteMarker direction,
    required List<String> ignoreRelays,
  }) async {
    List<String> combindedPubkeys = [
      ...?filter.authors,
      ...?filter.pTags,
    ]; // not perfect but probably fine, request got split earlier

    List<CoveragePubkey> coveragePubkeys = [
      for (final pubkey in combindedPubkeys)
        CoveragePubkey(pubkey, desiredCoverage, desiredCoverage),
    ];

    // look for connected relays that cover the pubkey
    for (var connectedRelay in connectedRelays) {
      var coveredPubkeysForRelay = <String>[];

      for (var coveragePubkey in coveragePubkeys) {
        if (JitEngine.doesRelayCoverPubkey(
          connectedRelay,
          coveragePubkey.pubkey,
          direction,
        )) {
          coveredPubkeysForRelay.add(coveragePubkey.pubkey);
          coveragePubkey.missingCoverage--;
        }
      }

      if (coveredPubkeysForRelay.isEmpty) {
        continue;
      }

      plan.addPubkeys(connectedRelay.url, filter, coveredPubkeysForRelay);

      // clear out fully covered pubkeys
      _removeFullyCoveredPubkeys(coveragePubkeys);
    }

    if (coveragePubkeys.isEmpty) {
      // all pubkeys are covered by already connected relays
      return const [];
    }

    /// ### resolve not covered pubkeys ###
    // look in nip65 data for not covered pubkeys
    final List<UserRelayList> nip65Data;
    try {
      nip65Data = await UserRelayLists.getUserRelayListCacheLatest(
        pubkeys: coveragePubkeys.map((e) => e.pubkey).toList(),
        cacheManager: cacheManager,
      );
    } catch (error, stackTrace) {
      Logger.log.w(
        () => "Could not load relay lists; falling back to bootstrap relays",
        error: error,
        stackTrace: stackTrace,
      );
      RelayJitBlastAllStrategy.plan(
        plan: plan,
        filter: filter,
        pubkeys: coveragePubkeys.map((e) => e.pubkey),
        connectedRelays: connectedRelays,
        bootstrapRelays: bootstrapRelays,
      );
      return const [];
    }

    // by finding the best relays to connect and send out the request
    RelayRankingResult relayRanking = rankRelays(
      direction: direction,
      searchingPubkeys: coveragePubkeys,
      eventData: nip65Data,
      boostRelays: connectedRelays.map((e) => e.url).toList(),
      ignoreRelays: ignoreRelays,
    );

    final candidates = <JitRelayCandidate>[];
    for (final relayCandidate in relayRanking.ranking) {
      if (relayCandidate.score <= 0) {
        continue;
      }
      final url =
          cleanRelayUrl(relayCandidate.relayUrl) ?? relayCandidate.relayUrl;
      final pubkeys = relayCandidate.coveredPubkeys
          .map((e) => e.pubkey)
          .toList();
      final connected = connectedRelays
          .where((element) => element.url == url)
          .firstOrNull;
      if (connected == null) {
        candidates.add(JitRelayCandidate(url, filter, pubkeys, direction));
        continue;
      }
      connected.jitEngineData.addPubkeysToAssignedPubkeys(pubkeys, direction);
      plan.addPubkeys(connected.url, filter, pubkeys);
    }

    final notCovered = [
      for (final pubkey in relayRanking.notCoveredPubkeys)
        if (pubkey.missingCoverage > 0) pubkey.pubkey,
    ];
    if (notCovered.isNotEmpty) {
      RelayJitBlastAllStrategy.plan(
        plan: plan,
        filter: filter,
        pubkeys: notCovered,
        connectedRelays: connectedRelays,
        bootstrapRelays: bootstrapRelays,
      );
    }
    return candidates;
  }

  /// Connects to [candidates], all at once, and sends each the request as soon
  /// as it is up. The pubkeys of a relay that cannot be reached go to the
  /// connected bootstrap relays that have not received the request yet; when
  /// every one of them has, they stay uncovered.
  static Future<void> connectCandidates({
    required List<JitRelayCandidate> candidates,
    required JitRequestPlan plan,
    required RelayManager relayManager,
    required List<String> bootstrapRelays,
  }) async {
    final unreachable = <JitRelayCandidate>[];
    final candidatesByUrl = <String, List<JitRelayCandidate>>{};
    for (final candidate in candidates) {
      candidatesByUrl.putIfAbsent(candidate.url, () => []).add(candidate);
    }

    // Awaiting each candidate in turn would make an unreachable relay consume
    // the full connection timeout before the next useful one is even tried.
    await Future.wait(
      candidatesByUrl.entries.map((entry) async {
        final url = entry.key;
        final result = await relayManager.connectRelay(dirtyUrl: url);
        final connectivity = relayManager.getRelayConnectivity(url);
        if (!result.connected || connectivity == null) {
          Logger.log.w(
            () => "Could not connect to relay: $url - errorHandling",
          );
          unreachable.addAll(entry.value);
          return;
        }
        for (final candidate in entry.value) {
          connectivity.jitEngineData.addPubkeysToAssignedPubkeys(
            candidate.pubkeys,
            candidate.direction,
          );
          plan.addPubkeys(url, candidate.filter, candidate.pubkeys);
        }
        plan.flush();
      }),
    );

    if (unreachable.isEmpty) return;
    final fallbackRelays = relayManager.connectedAnonymousRelays
        .where((relay) => !plan.isSent(relay.url))
        .toList();
    for (final candidate in unreachable) {
      RelayJitBlastAllStrategy.plan(
        plan: plan,
        filter: candidate.filter,
        pubkeys: candidate.pubkeys,
        connectedRelays: fallbackRelays,
        bootstrapRelays: bootstrapRelays,
      );
    }
    plan.flush();
  }
}

void _removeFullyCoveredPubkeys(List<CoveragePubkey> coveragePubkeys) {
  coveragePubkeys.removeWhere((element) => element.missingCoverage == 0);
}

class CoveragePubkey {
  final String pubkey;
  int desiredCoverage;
  int missingCoverage;

  CoveragePubkey(this.pubkey, this.desiredCoverage, this.missingCoverage);

  @override
  operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CoveragePubkey &&
        other.pubkey == pubkey &&
        other.desiredCoverage == desiredCoverage &&
        other.missingCoverage == missingCoverage;
  }

  @override
  int get hashCode =>
      pubkey.hashCode ^ desiredCoverage.hashCode ^ missingCoverage.hashCode;
}
