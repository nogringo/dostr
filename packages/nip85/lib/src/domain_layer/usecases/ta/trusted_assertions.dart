import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';

import '../../../config/nip85_defaults.dart';
import '../../entities/nip_85.dart';

/// The events matching [filter] on [relay]. Cached events may answer too, and
/// the events the relay sends should be cached.
typedef Nip85Query =
    Future<List<Nip01Event>> Function(Filter filter, {required String relay});

/// A live subscription: the [events] it receives, and [close] to end it.
typedef Nip85Subscription = ({
  Stream<Nip01Event> events,
  Future<void> Function() close,
});

/// Opens a live subscription to [filter] on [relay].
typedef Nip85Subscribe =
    Nip85Subscription Function(Filter filter, {required String relay});

/// Trusted Assertions usecase (NIP-85)
///
/// Allows fetching pre-computed metrics from trusted service providers.
class TrustedAssertions {
  final Nip85Query _query;
  final Nip85Subscribe _subscribe;
  final List<Nip85TrustedProvider> _defaultProviders;

  /// [query] answers the `get*` methods and [subscribe] the `stream*` ones.
  /// [defaultProviders] are asked when a call names no providers.
  TrustedAssertions({
    required Nip85Query query,
    required Nip85Subscribe subscribe,
    List<Nip85TrustedProvider> defaultProviders = DEFAULT_NIP85_PROVIDERS,
  }) : _query = query,
       _subscribe = subscribe,
       _defaultProviders = defaultProviders;

  /// Filter providers by kind and optionally by metrics
  List<Nip85TrustedProvider> _filterProviders(
    List<Nip85TrustedProvider> providers, {
    required int kind,
    Set<Nip85Metric>? metrics,
  }) {
    return providers.where((p) {
      // Must match the kind
      if (p.kind != kind) return false;
      // If metrics specified, must match one of them
      if (metrics != null && metrics.isNotEmpty) {
        return metrics.contains(p.metric);
      }
      return true;
    }).toList();
  }

  /// Get user metrics from trusted providers
  ///
  /// [pubkey] - The public key of the user to get metrics for
  /// [metrics] - Optional set of specific metrics to fetch. If null, fetches all available.
  /// [providers] - Optional list of providers to use. If null, uses default providers.
  ///
  /// Returns [Nip85UserMetrics] or null if no assertion found.
  Future<Nip85UserMetrics?> getUserMetrics(
    String pubkey, {
    Set<Nip85Metric>? metrics,
    List<Nip85TrustedProvider>? providers,
  }) async {
    final effectiveProviders = _filterProviders(
      providers ?? _defaultProviders,
      kind: Nip85Kind.user,
      metrics: metrics,
    );

    if (effectiveProviders.isEmpty) {
      return null;
    }

    // Group providers by relay for efficient querying
    final providersByRelay = <String, List<Nip85TrustedProvider>>{};
    for (final provider in effectiveProviders) {
      providersByRelay.putIfAbsent(provider.relay, () => []).add(provider);
    }

    final aggregatedMetrics = <Nip85Metric, dynamic>{};
    final metricCreatedAt = <Nip85Metric, int>{};
    final topics = <String>{};
    String? latestProviderPubkey;
    String? latestPubkey;
    int latestCreatedAt = 0;

    // Query each relay
    for (final entry in providersByRelay.entries) {
      final relay = entry.key;
      final relayProviders = entry.value;
      final providerPubkeys = relayProviders.map((p) => p.pubkey).toList();

      try {
        final events = await _query(
          Filter(
            kinds: [Nip85Kind.user],
            authors: providerPubkeys,
            dTags: [pubkey],
            limit: providerPubkeys.length,
          ),
          relay: relay,
        );
        for (final event in events) {
          final parsed = _parseUserMetricsEvent(event, metrics);
          if (parsed == null) continue;

          parsed.metrics.forEach((metric, value) {
            final currentMetricCreatedAt = metricCreatedAt[metric] ?? -1;
            if (parsed.createdAt >= currentMetricCreatedAt) {
              aggregatedMetrics[metric] = value;
              metricCreatedAt[metric] = parsed.createdAt;
            }
          });

          if (parsed.createdAt >= latestCreatedAt) {
            latestCreatedAt = parsed.createdAt;
            latestProviderPubkey = parsed.providerPubkey;
            latestPubkey = parsed.pubkey;
            topics
              ..clear()
              ..addAll(parsed.topics);
          }
        }
      } catch (_) {
        // Continue with other relays if one fails
      }
    }

    if (latestProviderPubkey == null) {
      return null;
    }

    return Nip85UserMetrics(
      pubkey: latestPubkey ?? pubkey,
      providerPubkey: latestProviderPubkey,
      createdAt: latestCreatedAt,
      metrics: aggregatedMetrics,
      topics: topics.toList(),
    );
  }

  /// Stream user metrics from trusted providers
  ///
  /// [pubkey] - The public key of the user to get metrics for
  /// [metrics] - Optional set of specific metrics to fetch. If null, fetches all available.
  /// [providers] - Optional list of providers to use. If null, uses default providers.
  ///
  /// Returns a [Stream] of [Nip85UserMetrics] that emits updates as they arrive.
  Stream<Nip85UserMetrics> streamUserMetrics(
    String pubkey, {
    Set<Nip85Metric>? metrics,
    List<Nip85TrustedProvider>? providers,
  }) {
    final effectiveProviders = _filterProviders(
      providers ?? _defaultProviders,
      kind: Nip85Kind.user,
      metrics: metrics,
    );

    final controller = StreamController<Nip85UserMetrics>();

    if (effectiveProviders.isEmpty) {
      controller.close();
      return controller.stream;
    }

    // Group providers by relay
    final providersByRelay = <String, List<Nip85TrustedProvider>>{};
    for (final provider in effectiveProviders) {
      providersByRelay.putIfAbsent(provider.relay, () => []).add(provider);
    }

    final subscriptions = <Nip85Subscription>[];
    final aggregatedMetrics = <Nip85Metric, dynamic>{};
    final metricCreatedAt = <Nip85Metric, int>{};
    final topics = <String>{};
    String? latestProviderPubkey;
    String? latestPubkey;
    int latestCreatedAt = 0;

    // Subscribe to each relay
    for (final entry in providersByRelay.entries) {
      final relay = entry.key;
      final relayProviders = entry.value;
      final providerPubkeys = relayProviders.map((p) => p.pubkey).toList();

      final subscription = _subscribe(
        Filter(
          kinds: [Nip85Kind.user],
          authors: providerPubkeys,
          dTags: [pubkey],
        ),
        relay: relay,
      );

      subscriptions.add(subscription);

      subscription.events.listen(
        (event) {
          final parsed = _parseUserMetricsEvent(event, metrics);
          if (parsed == null) return;

          parsed.metrics.forEach((metric, value) {
            final currentMetricCreatedAt = metricCreatedAt[metric] ?? -1;
            if (parsed.createdAt >= currentMetricCreatedAt) {
              aggregatedMetrics[metric] = value;
              metricCreatedAt[metric] = parsed.createdAt;
            }
          });

          if (parsed.createdAt >= latestCreatedAt) {
            latestCreatedAt = parsed.createdAt;
            latestProviderPubkey = parsed.providerPubkey;
            latestPubkey = parsed.pubkey;
            topics
              ..clear()
              ..addAll(parsed.topics);
          }

          if (latestProviderPubkey != null) {
            controller.add(
              Nip85UserMetrics(
                pubkey: latestPubkey ?? pubkey,
                providerPubkey: latestProviderPubkey!,
                createdAt: latestCreatedAt,
                metrics: Map.from(aggregatedMetrics),
                topics: topics.toList(),
              ),
            );
          }
        },
        onError: (e) {
          // Ignore errors from individual relays
        },
      );
    }

    // Close subscriptions when stream is cancelled
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.close();
      }
    };

    return controller.stream;
  }

  /// Parse a NIP-85 kind 30382 event into [Nip85UserMetrics]
  Nip85UserMetrics? _parseUserMetricsEvent(
    Nip01Event event,
    Set<Nip85Metric>? requestedMetrics,
  ) {
    if (event.kind != Nip85Kind.user) return null;

    final dTag = event.dTag;
    if (dTag == null) return null;

    final metricsMap = <Nip85Metric, dynamic>{};
    final topics = <String>[];

    for (final tag in event.tags) {
      if (tag.length < 2) continue;

      final tagName = tag[0];
      final tagValue = tag[1];

      // Handle topic tags
      if (tagName == 't') {
        topics.add(tagValue);
        continue;
      }

      // Try to parse as metric
      final metric = Nip85Metric.fromTagName(tagName);
      if (metric != null) {
        // If specific metrics requested, filter
        if (requestedMetrics != null && !requestedMetrics.contains(metric)) {
          continue;
        }

        // Parse value based on metric type
        final parsedValue = int.tryParse(tagValue);
        if (parsedValue != null) {
          metricsMap[metric] = parsedValue;
        }
      }
    }

    return Nip85UserMetrics(
      pubkey: dTag,
      providerPubkey: event.pubKey,
      createdAt: event.createdAt,
      metrics: metricsMap,
      topics: topics,
    );
  }

  // ===========================================================================
  // EVENT METRICS (kind 30383)
  // ===========================================================================

  /// Get event metrics from trusted providers
  ///
  /// [eventId] - The event ID to get metrics for
  /// [metrics] - Optional set of specific metrics to fetch. If null, fetches all available.
  /// [providers] - Optional list of providers to use. If null, uses default providers.
  ///
  /// Returns [Nip85EventMetrics] or null if no assertion found.
  Future<Nip85EventMetrics?> getEventMetrics(
    String eventId, {
    Set<Nip85Metric>? metrics,
    List<Nip85TrustedProvider>? providers,
  }) async {
    final effectiveProviders = _filterProviders(
      providers ?? _defaultProviders,
      kind: Nip85Kind.event,
      metrics: metrics,
    );

    if (effectiveProviders.isEmpty) {
      return null;
    }

    // Group providers by relay for efficient querying
    final providersByRelay = <String, List<Nip85TrustedProvider>>{};
    for (final provider in effectiveProviders) {
      providersByRelay.putIfAbsent(provider.relay, () => []).add(provider);
    }

    final aggregatedMetrics = <Nip85Metric, dynamic>{};
    final metricCreatedAt = <Nip85Metric, int>{};
    String? latestProviderPubkey;
    String? latestEventId;
    int latestCreatedAt = 0;

    // Query each relay
    for (final entry in providersByRelay.entries) {
      final relay = entry.key;
      final relayProviders = entry.value;
      final providerPubkeys = relayProviders.map((p) => p.pubkey).toList();

      try {
        final events = await _query(
          Filter(
            kinds: [Nip85Kind.event],
            authors: providerPubkeys,
            dTags: [eventId],
            limit: providerPubkeys.length,
          ),
          relay: relay,
        );
        for (final event in events) {
          final parsed = _parseEventMetricsEvent(event, metrics);
          if (parsed == null) continue;

          parsed.metrics.forEach((metric, value) {
            final currentMetricCreatedAt = metricCreatedAt[metric] ?? -1;
            if (parsed.createdAt >= currentMetricCreatedAt) {
              aggregatedMetrics[metric] = value;
              metricCreatedAt[metric] = parsed.createdAt;
            }
          });

          if (parsed.createdAt >= latestCreatedAt) {
            latestCreatedAt = parsed.createdAt;
            latestProviderPubkey = parsed.providerPubkey;
            latestEventId = parsed.eventId;
          }
        }
      } catch (_) {
        // Continue with other relays if one fails
      }
    }

    if (aggregatedMetrics.isEmpty || latestProviderPubkey == null) {
      return null;
    }

    return Nip85EventMetrics(
      eventId: latestEventId ?? eventId,
      providerPubkey: latestProviderPubkey,
      createdAt: latestCreatedAt,
      metrics: aggregatedMetrics,
    );
  }

  /// Stream event metrics from trusted providers
  ///
  /// [eventId] - The event ID to get metrics for
  /// [metrics] - Optional set of specific metrics to fetch. If null, fetches all available.
  /// [providers] - Optional list of providers to use. If null, uses default providers.
  ///
  /// Returns a [Stream] of [Nip85EventMetrics] that emits updates as they arrive.
  Stream<Nip85EventMetrics> streamEventMetrics(
    String eventId, {
    Set<Nip85Metric>? metrics,
    List<Nip85TrustedProvider>? providers,
  }) {
    final effectiveProviders = _filterProviders(
      providers ?? _defaultProviders,
      kind: Nip85Kind.event,
      metrics: metrics,
    );

    final controller = StreamController<Nip85EventMetrics>();

    if (effectiveProviders.isEmpty) {
      controller.close();
      return controller.stream;
    }

    // Group providers by relay
    final providersByRelay = <String, List<Nip85TrustedProvider>>{};
    for (final provider in effectiveProviders) {
      providersByRelay.putIfAbsent(provider.relay, () => []).add(provider);
    }

    final subscriptions = <Nip85Subscription>[];
    final aggregatedMetrics = <Nip85Metric, dynamic>{};
    final metricCreatedAt = <Nip85Metric, int>{};
    String? latestProviderPubkey;
    int latestCreatedAt = 0;

    // Subscribe to each relay
    for (final entry in providersByRelay.entries) {
      final relay = entry.key;
      final relayProviders = entry.value;
      final providerPubkeys = relayProviders.map((p) => p.pubkey).toList();

      final subscription = _subscribe(
        Filter(
          kinds: [Nip85Kind.event],
          authors: providerPubkeys,
          dTags: [eventId],
        ),
        relay: relay,
      );

      subscriptions.add(subscription);

      subscription.events.listen(
        (event) {
          final parsed = _parseEventMetricsEvent(event, metrics);
          if (parsed == null) return;

          parsed.metrics.forEach((metric, value) {
            final currentMetricCreatedAt = metricCreatedAt[metric] ?? -1;
            if (parsed.createdAt >= currentMetricCreatedAt) {
              aggregatedMetrics[metric] = value;
              metricCreatedAt[metric] = parsed.createdAt;
            }
          });

          if (parsed.createdAt >= latestCreatedAt) {
            latestCreatedAt = parsed.createdAt;
            latestProviderPubkey = parsed.providerPubkey;
          }

          if (aggregatedMetrics.isNotEmpty && latestProviderPubkey != null) {
            controller.add(
              Nip85EventMetrics(
                eventId: eventId,
                providerPubkey: latestProviderPubkey!,
                createdAt: latestCreatedAt,
                metrics: Map.from(aggregatedMetrics),
              ),
            );
          }
        },
        onError: (e) {
          // Ignore errors from individual relays
        },
      );
    }

    // Close subscriptions when stream is cancelled
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.close();
      }
    };

    return controller.stream;
  }

  /// Parse a NIP-85 kind 30383 event into [Nip85EventMetrics]
  Nip85EventMetrics? _parseEventMetricsEvent(
    Nip01Event event,
    Set<Nip85Metric>? requestedMetrics,
  ) {
    if (event.kind != Nip85Kind.event) return null;

    final dTag = event.dTag;
    if (dTag == null) return null;

    final metricsMap = <Nip85Metric, dynamic>{};

    for (final tag in event.tags) {
      if (tag.length < 2) continue;

      final tagName = tag[0];
      final tagValue = tag[1];

      // Try to parse as metric
      final metric = Nip85Metric.fromTagName(tagName);
      if (metric != null) {
        // If specific metrics requested, filter
        if (requestedMetrics != null && !requestedMetrics.contains(metric)) {
          continue;
        }

        // Parse value based on metric type
        final parsedValue = int.tryParse(tagValue);
        if (parsedValue != null) {
          metricsMap[metric] = parsedValue;
        }
      }
    }

    return Nip85EventMetrics(
      eventId: dTag,
      providerPubkey: event.pubKey,
      createdAt: event.createdAt,
      metrics: metricsMap,
    );
  }

  // ===========================================================================
  // ADDRESSABLE METRICS (kind 30384)
  // ===========================================================================

  /// Get addressable event metrics from trusted providers
  ///
  /// [eventAddress] - The event address (kind:pubkey:d-tag) to get metrics for
  /// [metrics] - Optional set of specific metrics to fetch. If null, fetches all available.
  /// [providers] - Optional list of providers to use. If null, uses default providers.
  ///
  /// Returns [Nip85AddressableMetrics] or null if no assertion found.
  Future<Nip85AddressableMetrics?> getAddressableMetrics(
    String eventAddress, {
    Set<Nip85Metric>? metrics,
    List<Nip85TrustedProvider>? providers,
  }) async {
    final effectiveProviders = _filterProviders(
      providers ?? _defaultProviders,
      kind: Nip85Kind.addressable,
      metrics: metrics,
    );

    if (effectiveProviders.isEmpty) {
      return null;
    }

    final providersByRelay = <String, List<Nip85TrustedProvider>>{};
    for (final provider in effectiveProviders) {
      providersByRelay.putIfAbsent(provider.relay, () => []).add(provider);
    }

    Nip85AddressableMetrics? result;
    int latestCreatedAt = 0;

    for (final entry in providersByRelay.entries) {
      final relay = entry.key;
      final relayProviders = entry.value;
      final providerPubkeys = relayProviders.map((p) => p.pubkey).toList();

      try {
        final events = await _query(
          Filter(
            kinds: [Nip85Kind.addressable],
            authors: providerPubkeys,
            dTags: [eventAddress],
            limit: providerPubkeys.length,
          ),
          relay: relay,
        );
        for (final event in events) {
          final parsed = _parseAddressableMetricsEvent(event, metrics);
          if (parsed != null && parsed.createdAt > latestCreatedAt) {
            result = parsed;
            latestCreatedAt = parsed.createdAt;
          }
        }
      } catch (_) {}
    }

    return result;
  }

  /// Stream addressable event metrics from trusted providers
  Stream<Nip85AddressableMetrics> streamAddressableMetrics(
    String eventAddress, {
    Set<Nip85Metric>? metrics,
    List<Nip85TrustedProvider>? providers,
  }) {
    final effectiveProviders = _filterProviders(
      providers ?? _defaultProviders,
      kind: Nip85Kind.addressable,
      metrics: metrics,
    );

    final controller = StreamController<Nip85AddressableMetrics>();

    if (effectiveProviders.isEmpty) {
      controller.close();
      return controller.stream;
    }

    final providersByRelay = <String, List<Nip85TrustedProvider>>{};
    for (final provider in effectiveProviders) {
      providersByRelay.putIfAbsent(provider.relay, () => []).add(provider);
    }

    final subscriptions = <Nip85Subscription>[];

    for (final entry in providersByRelay.entries) {
      final relay = entry.key;
      final relayProviders = entry.value;
      final providerPubkeys = relayProviders.map((p) => p.pubkey).toList();

      final subscription = _subscribe(
        Filter(
          kinds: [Nip85Kind.addressable],
          authors: providerPubkeys,
          dTags: [eventAddress],
        ),
        relay: relay,
      );

      subscriptions.add(subscription);

      subscription.events.listen((event) {
        final parsed = _parseAddressableMetricsEvent(event, metrics);
        if (parsed != null) {
          controller.add(parsed);
        }
      }, onError: (e) {});
    }

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.close();
      }
    };

    return controller.stream;
  }

  Nip85AddressableMetrics? _parseAddressableMetricsEvent(
    Nip01Event event,
    Set<Nip85Metric>? requestedMetrics,
  ) {
    if (event.kind != Nip85Kind.addressable) return null;

    final dTag = event.dTag;
    if (dTag == null) return null;

    final metricsMap = <Nip85Metric, dynamic>{};

    for (final tag in event.tags) {
      if (tag.length < 2) continue;

      final metric = Nip85Metric.fromTagName(tag[0]);
      if (metric != null) {
        if (requestedMetrics != null && !requestedMetrics.contains(metric)) {
          continue;
        }
        final parsedValue = int.tryParse(tag[1]);
        if (parsedValue != null) {
          metricsMap[metric] = parsedValue;
        }
      }
    }

    return Nip85AddressableMetrics(
      eventAddress: dTag,
      providerPubkey: event.pubKey,
      createdAt: event.createdAt,
      metrics: metricsMap,
    );
  }

  // ===========================================================================
  // EXTERNAL ID METRICS (kind 30385)
  // ===========================================================================

  /// Get external identifier metrics from trusted providers (NIP-73)
  ///
  /// [identifier] - The NIP-73 i-tag value to get metrics for
  /// [metrics] - Optional set of specific metrics to fetch. If null, fetches all available.
  /// [providers] - Optional list of providers to use. If null, uses default providers.
  ///
  /// Returns [Nip85ExternalIdMetrics] or null if no assertion found.
  Future<Nip85ExternalIdMetrics?> getExternalIdMetrics(
    String identifier, {
    Set<Nip85Metric>? metrics,
    List<Nip85TrustedProvider>? providers,
  }) async {
    final effectiveProviders = _filterProviders(
      providers ?? _defaultProviders,
      kind: Nip85Kind.externalId,
      metrics: metrics,
    );

    if (effectiveProviders.isEmpty) {
      return null;
    }

    final providersByRelay = <String, List<Nip85TrustedProvider>>{};
    for (final provider in effectiveProviders) {
      providersByRelay.putIfAbsent(provider.relay, () => []).add(provider);
    }

    Nip85ExternalIdMetrics? result;
    int latestCreatedAt = 0;

    for (final entry in providersByRelay.entries) {
      final relay = entry.key;
      final relayProviders = entry.value;
      final providerPubkeys = relayProviders.map((p) => p.pubkey).toList();

      try {
        final events = await _query(
          Filter(
            kinds: [Nip85Kind.externalId],
            authors: providerPubkeys,
            dTags: [identifier],
            limit: providerPubkeys.length,
          ),
          relay: relay,
        );
        for (final event in events) {
          final parsed = _parseExternalIdMetricsEvent(event, metrics);
          if (parsed != null && parsed.createdAt > latestCreatedAt) {
            result = parsed;
            latestCreatedAt = parsed.createdAt;
          }
        }
      } catch (_) {}
    }

    return result;
  }

  /// Stream external identifier metrics from trusted providers (NIP-73)
  Stream<Nip85ExternalIdMetrics> streamExternalIdMetrics(
    String identifier, {
    Set<Nip85Metric>? metrics,
    List<Nip85TrustedProvider>? providers,
  }) {
    final effectiveProviders = _filterProviders(
      providers ?? _defaultProviders,
      kind: Nip85Kind.externalId,
      metrics: metrics,
    );

    final controller = StreamController<Nip85ExternalIdMetrics>();

    if (effectiveProviders.isEmpty) {
      controller.close();
      return controller.stream;
    }

    final providersByRelay = <String, List<Nip85TrustedProvider>>{};
    for (final provider in effectiveProviders) {
      providersByRelay.putIfAbsent(provider.relay, () => []).add(provider);
    }

    final subscriptions = <Nip85Subscription>[];

    for (final entry in providersByRelay.entries) {
      final relay = entry.key;
      final relayProviders = entry.value;
      final providerPubkeys = relayProviders.map((p) => p.pubkey).toList();

      final subscription = _subscribe(
        Filter(
          kinds: [Nip85Kind.externalId],
          authors: providerPubkeys,
          dTags: [identifier],
        ),
        relay: relay,
      );

      subscriptions.add(subscription);

      subscription.events.listen((event) {
        final parsed = _parseExternalIdMetricsEvent(event, metrics);
        if (parsed != null) {
          controller.add(parsed);
        }
      }, onError: (e) {});
    }

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.close();
      }
    };

    return controller.stream;
  }

  Nip85ExternalIdMetrics? _parseExternalIdMetricsEvent(
    Nip01Event event,
    Set<Nip85Metric>? requestedMetrics,
  ) {
    if (event.kind != Nip85Kind.externalId) return null;

    final dTag = event.dTag;
    if (dTag == null) return null;

    final metricsMap = <Nip85Metric, dynamic>{};

    for (final tag in event.tags) {
      if (tag.length < 2) continue;

      final metric = Nip85Metric.fromTagName(tag[0]);
      if (metric != null) {
        if (requestedMetrics != null && !requestedMetrics.contains(metric)) {
          continue;
        }
        final parsedValue = int.tryParse(tag[1]);
        if (parsedValue != null) {
          metricsMap[metric] = parsedValue;
        }
      }
    }

    return Nip85ExternalIdMetrics(
      identifier: dTag,
      providerPubkey: event.pubKey,
      createdAt: event.createdAt,
      metrics: metricsMap,
    );
  }
}
