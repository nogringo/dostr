import 'dart:async';

import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'package:ndk_logger/ndk_logger.dart';
import '../../entities/jit_engine_relay_connectivity_data.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import '../engines/network_engine.dart';
import 'relay_jit_request_strategies/relay_jit_blast_all_strategy.dart';
import 'relay_jit_request_strategies/relay_jit_pubkey_strategy.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import 'jit_request_plan.dart';

/// Just In Time Network Engine
/// This engine is responsible for handling all nostr network requests
class JitEngine with Logger implements NetworkEngine {
  /// cache manager for caching events
  CacheManager cache;

  /// relays to ignore
  List<String> ignoreRelays;

  /// manager for all relays
  RelayManager relayManagerLight;

  /// ndk config
  List<String> bootstrapRelays;

  final Future<void> _bootstrapRelaysConnected;

  /// Creates a new JIT engine.
  ///
  /// Requests wait for [bootstrapRelaysConnected], if given, before they are
  /// routed.
  JitEngine({
    required this.relayManagerLight,
    required this.cache,
    required this.ignoreRelays,
    required this.bootstrapRelays,
    Future<void>? bootstrapRelaysConnected,
  }) : _bootstrapRelaysConnected = bootstrapRelaysConnected ?? Future.value();

  /// Finds the right relays for each filter. The connected ones get the
  /// request before this completes; the others are connected to afterwards,
  /// without holding the request open. If no relay is found the request is
  /// blasted to the connected bootstrap relays.
  @override
  Future<void> route(
    List<Filter> filters,
    RelaySend send, {
    RelaySet? relaySet,
    required int desiredCoverage,
  }) async {
    await _bootstrapRelaysConnected;

    final plan = JitRequestPlan(send);
    final connectedRelays = relayManagerLight.connectedAnonymousRelays;
    final cleanIgnoreRelays = cleanRelayUrls(ignoreRelays);
    final candidates = <JitRelayCandidate>[];

    for (final filter in filters) {
      final ReadWriteMarker direction;
      if (filter.authors?.isNotEmpty ?? false) {
        // the author should write on the persons write relays
        direction = ReadWriteMarker.writeOnly;
      } else if (filter.pTags?.isNotEmpty ?? false) {
        // others should mention on the persons read relays
        direction = ReadWriteMarker.readOnly;
      } else {
        if (filter.search != null) {
          Logger.log.w(
            () => "search filter not implemented yet, using blast all strategy",
          );
        }
        RelayJitBlastAllStrategy.plan(
          plan: plan,
          filter: filter,
          connectedRelays: connectedRelays,
          bootstrapRelays: bootstrapRelays,
        );
        continue;
      }

      candidates.addAll(
        await RelayJitPubkeyStrategy.plan(
          plan: plan,
          filter: filter,
          connectedRelays: connectedRelays,
          bootstrapRelays: bootstrapRelays,
          cacheManager: cache,
          desiredCoverage: desiredCoverage,
          direction: direction,
          ignoreRelays: cleanIgnoreRelays,
        ),
      );
    }
    plan.flush();

    if (candidates.isEmpty) return;
    final connecting = RelayJitPubkeyStrategy.connectCandidates(
      candidates: candidates,
      plan: plan,
      relayManager: relayManagerLight,
      bootstrapRelays: bootstrapRelays,
    );
    // a request no relay serves yet has nothing to end on but these
    if (!plan.hasSent) return connecting;
    unawaited(
      connecting.catchError((Object error, StackTrace stackTrace) {
        Logger.log.e(
          () => "connecting relay candidates failed",
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  /// checks if relay covers given pubkey in given direction
  static bool doesRelayCoverPubkey(
    RelayConnectivity relay,
    String pubkey,
    ReadWriteMarker direction,
  ) {
    for (RelayJitAssignedPubkey assignedPubkey
        in relay.jitEngineData.assignedPubkeys) {
      if (assignedPubkey.pubkey == pubkey) {
        switch (direction) {
          case ReadWriteMarker.readOnly:
            return assignedPubkey.direction.isRead;
          case ReadWriteMarker.writeOnly:
            return assignedPubkey.direction.isWrite;
          case ReadWriteMarker.readWrite:
            return assignedPubkey.direction == ReadWriteMarker.readWrite;
        }
      }
    }
    return false;
  }
}
