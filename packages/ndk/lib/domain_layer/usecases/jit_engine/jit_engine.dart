import 'dart:async';

import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'package:ndk_core/shared/logger/logger.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_response.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_state.dart';
import '../../entities/contact_list.dart';
import '../../entities/jit_engine_relay_connectivity_data.dart';
import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import '../../entities/read_write_marker.dart';
import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import '../../entities/relay_set.dart';
import '../../repositories/cache_manager.dart';
import 'package:ndk_core/domain_layer/repositories/event_signer.dart';
import '../engines/network_engine.dart';
import 'relay_jit_broadcast_strategies/relay_jit_broadcast_other_read.dart';
import 'relay_jit_broadcast_strategies/relay_jit_broadcast_own.dart';
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

  /// Creates a new JIT engine.
  JitEngine({
    required this.relayManagerLight,
    required this.cache,
    required this.ignoreRelays,
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

  /// broadcasts given event using inbox/outbox (gossip) if explicit relays are given they are used instead
  /// [nostrEvent] event to publish
  /// [explicitRelays] used instead of gossip if set

  @override
  NdkBroadcastResponse handleEventBroadcast({
    required Nip01Event nostrEvent,
    required EventSigner? signer,
    required BroadcastState broadcastState,
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

      final ownRelays = cleanRelayUrls(
        await RelayJitBroadcastOutboxStrategy.relays(
          eventToPublish: workingNostrEvent,
          cacheManager: cache,
          bootstrapRelays: bootstrapRelays,
        ),
      ).toSet();

      // check if we need to publish to others inboxes
      final inboxRelays =
          workingNostrEvent.pTags.isNotEmpty &&
              workingNostrEvent.kind != ContactList.kKind
          ? cleanRelayUrls(
              await RelayJitBroadcastOtherReadStrategy.relays(
                cacheManager: cache,
                pubkeysOfInbox: workingNostrEvent.pTags,
              ),
            ).toSet()
          : <String>{};

      // a relay in the outbox and an inbox gets the event once
      await Future.wait([
        for (final url in ownRelays)
          relayManagerLight.publishToRelay(
            broadcastState,
            url,
            workingNostrEvent,
          ),
        for (final url in inboxRelays.difference(ownRelays))
          relayManagerLight.publishToRelay(
            broadcastState,
            url,
            workingNostrEvent,
          ),
      ]);
      broadcastState.closeIfNoRelays();
    }

    asyncStuff();
    return NdkBroadcastResponse.fromState(nostrEvent, broadcastState);
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
