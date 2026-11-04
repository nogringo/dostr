import 'dart:async';

import '../../../shared/helpers/relay_helper.dart';
import '../../../shared/logger/logger.dart';
import '../../entities/broadcast_response.dart';
import '../../entities/broadcast_state.dart';
import '../../entities/contact_list.dart';
import '../../entities/global_state.dart';
import '../../entities/jit_engine_relay_connectivity_data.dart';
import '../../entities/nip_01_event.dart';
import '../../entities/read_write_marker.dart';
import '../../entities/relay_connectivity.dart';
import '../../entities/filter.dart';
import '../../entities/relay_set.dart';
import '../../repositories/cache_manager.dart';
import '../../repositories/event_signer.dart';
import '../engines/network_engine.dart';
import 'relay_jit_broadcast_strategies/relay_jit_broadcast_other_read.dart';
import 'relay_jit_broadcast_strategies/relay_jit_broadcast_own.dart';
import 'relay_jit_broadcast_strategies/relay_jit_broadcast_specific.dart';
import 'relay_jit_request_strategies/relay_jit_blast_all_strategy.dart';
import 'relay_jit_request_strategies/relay_jit_pubkey_strategy.dart';
import '../relay_manager.dart';
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

  /// global state of the ndk
  GlobalState globalState;

  /// ndk config
  List<String> bootstrapRelays;

  /// Creates a new JIT engine.
  JitEngine({
    required this.relayManagerLight,
    required this.cache,
    required this.ignoreRelays,
    required this.globalState,
    required this.bootstrapRelays,
  });

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
    await relayManagerLight.seedRelaysConnected;

    final plan = JitRequestPlan(send);
    final connectedRelays = relayManagerLight.connectedAnonymousRelays
        .whereType<RelayConnectivity<JitEngineRelayConnectivityData>>()
        .toList();
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
      globalState: globalState,
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

  /// broadcasts given event using inbox/outbox (gossip) if explicit relays are given they are used instead
  /// [nostrEvent] event to publish
  /// [explicitRelays] used instead of gossip if set

  @override
  NdkBroadcastResponse handleEventBroadcast({
    required Nip01Event nostrEvent,
    required EventSigner? signer,
    required BroadcastState broadcastState,
    Iterable<String>? specificRelays,
  }) {
    Future<void> asyncStuff() async {
      await relayManagerLight.seedRelaysConnected;

      final Nip01Event workingNostrEvent;
      try {
        if (signer != null) {
          workingNostrEvent = await signer.sign(nostrEvent);
        } else {
          workingNostrEvent = nostrEvent;
        }
      } catch (e, stackTrace) {
        broadcastState.addError(e, stackTrace);
        return;
      }
      broadcastState.startTimeout();

      if (specificRelays != null) {
        final cleanedSpecificRelays = cleanRelayUrls(specificRelays.toList());
        await RelayJitBroadcastSpecificRelaysStrategy.broadcast(
          specificRelays: cleanedSpecificRelays,
          relayManager: relayManagerLight,
          cacheManager: cache,
          eventToPublish: workingNostrEvent,
          broadcastState: broadcastState,
        );
        broadcastState.closeIfNoRelays();
        return;
      }

      // default publish to own outbox
      await RelayJitBroadcastOutboxStrategy.broadcast(
        eventToPublish: workingNostrEvent,
        cacheManager: cache,
        relayManager: relayManagerLight,
        bootstrapRelays: bootstrapRelays,
        broadcastState: broadcastState,
      );

      // check if we need to publish to others inboxes
      if (workingNostrEvent.pTags.isNotEmpty &&
          workingNostrEvent.kind != ContactList.kKind) {
        await RelayJitBroadcastOtherReadStrategy.broadcast(
          eventToPublish: workingNostrEvent,
          cacheManager: cache,
          relayManager: relayManagerLight,
          pubkeysOfInbox: workingNostrEvent.pTags,
          broadcastState: broadcastState,
        );
      }
      broadcastState.closeIfNoRelays();
    }

    asyncStuff();
    return NdkBroadcastResponse(
      publishEvent: nostrEvent,
      broadcastDoneStream: broadcastState.stateUpdates.map(
        (state) => state.broadcasts.values.toList(),
      ),
      broadcastDoneFuture: broadcastState.publishDoneFuture.then(
        (state) => state.broadcasts.values.toList(),
      ),
    );
  }

  /// checks if relay covers given pubkey in given direction
  static bool doesRelayCoverPubkey(
    RelayConnectivity<JitEngineRelayConnectivityData> relay,
    String pubkey,
    ReadWriteMarker direction,
  ) {
    for (RelayJitAssignedPubkey assignedPubkey
        in relay.specificEngineData!.assignedPubkeys) {
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
