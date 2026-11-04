export 'package:ndk_core/domain_layer/entities/engine_additional_data_factory.dart';

import 'package:ndk_core/domain_layer/entities/broadcast_response.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_state.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import '../../entities/relay_set.dart';
import 'package:ndk_core/domain_layer/repositories/event_signer.dart';

/// Hands [filters] to [relayUrl] in a single REQ.
typedef RelaySend = void Function(String relayUrl, List<Filter> filters);

abstract class NetworkEngine {
  /// Picks the relays [filters] go to and hands each of them to [send], at
  /// most once per relay: a second REQ with the same id would replace the first
  /// on the relay (NIP-01).
  ///
  /// The request may end once the returned future completes and the relays
  /// handed over so far answered. A relay handed over later, one the engine was
  /// still connecting to, only gets the request if it is still running.
  Future<void> route(
    List<Filter> filters,
    RelaySend send, {
    RelaySet? relaySet,
    required int desiredCoverage,
  });

  /// Signs [nostrEvent] with [signer] when given, then publishes it to the
  /// author's outbox relays and the inboxes it mentions.
  NdkBroadcastResponse handleEventBroadcast({
    required Nip01Event nostrEvent,
    required EventSigner? signer,
    required BroadcastState broadcastState,
  });
}
