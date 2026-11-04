import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';
import '../jit_request_plan.dart';

/// Strategy Description:
///
/// blast the request to all connected bootstrap relays without adding the
/// pubkey to the relay
///
class RelayJitBlastAllStrategy {
  /// Adds [filter] to [plan] for every connected bootstrap relay, restricted to
  /// [pubkeys] when given.
  static void plan({
    required JitRequestPlan plan,
    required Filter filter,
    Iterable<String>? pubkeys,
    required Iterable<RelayConnectivity> connectedRelays,
    required List<String> bootstrapRelays,
  }) {
    for (final connectedRelay in connectedRelays) {
      if (!bootstrapRelays.contains(connectedRelay.url)) continue;
      if (pubkeys == null) {
        plan.addFilter(connectedRelay.url, filter);
      } else {
        plan.addPubkeys(connectedRelay.url, filter, pubkeys);
      }
    }
  }
}
