import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_cache/ndk_cache.dart';

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
}
