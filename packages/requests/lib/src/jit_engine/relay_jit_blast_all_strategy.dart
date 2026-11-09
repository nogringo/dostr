import 'package:ndk_nip01/ndk_nip01.dart';
import 'jit_request_plan.dart';

/// Strategy Description:
///
/// blast the request to all bootstrap relays without adding the pubkey to the
/// relay
///
class RelayJitBlastAllStrategy {
  /// Adds [filter] to [plan] for every relay of [relays], restricted to
  /// [pubkeys] when given. The ones not connected yet are connected to when
  /// the plan sends to them.
  static void plan({
    required JitRequestPlan plan,
    required Filter filter,
    Iterable<String>? pubkeys,
    required Iterable<String> relays,
  }) {
    for (final url in relays) {
      if (pubkeys == null) {
        plan.addFilter(url, filter);
      } else {
        plan.addPubkeys(url, filter, pubkeys);
      }
    }
  }
}
