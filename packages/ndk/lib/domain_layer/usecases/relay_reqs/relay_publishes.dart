import 'dart:async';

import '../../../config/broadcast_defaults.dart';
import '../../../shared/helpers/relay_helper.dart';
import '../../entities/auth_policy.dart';
import '../../entities/broadcast_response.dart';
import '../../entities/broadcast_state.dart';
import '../../entities/nip_01_event.dart';
import '../relay_manager.dart';

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
    final state = BroadcastState(
      timeout: timeout,
      considerDonePercent: considerDonePercent,
      auth: auth,
    );
    _relayManager.trackBroadcast(event, state);
    state.startTimeout();

    Future<void> send() async {
      await Future.wait([
        for (final url in cleanRelayUrls(relays.toList()).toSet())
          _relayManager.publishToRelay(state, url, event),
      ]);
      state.closeIfNoRelays();
    }

    unawaited(send());
    return NdkBroadcastResponse.fromState(event, state);
  }
}
