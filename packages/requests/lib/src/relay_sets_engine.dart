import 'dart:core';

import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'network_engine.dart';

class RelaySetsEngine implements NetworkEngine {
  static const Duration kDefaultStreamIdleTimeout = Duration(seconds: 5);

  final List<String> _bootstrapRelays;

  /// engine that pre-calculates relay sets for gossip
  RelaySetsEngine({required List<String> bootstrapRelays})
    : _bootstrapRelays = bootstrapRelays;

  @override
  Future<void> route(
    List<Filter> filters,
    RelaySend send, {
    RelaySet? relaySet,
    required int desiredCoverage,
  }) async {
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
}
