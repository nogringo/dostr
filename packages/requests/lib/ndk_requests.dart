/// Queries and subscriptions for NDK, routed to the outbox relays of their
/// authors.
///
/// ```dart
/// final requests = Requests(
///   cacheRead: CacheRead(cache),
///   cacheManager: cache,
///   networkEngine: JitEngine(
///     relayManagerLight: relayManager,
///     cache: cache,
///     ignoreRelays: const [],
///     bootstrapRelays: bootstrapRelays,
///   ),
///   relayManager: relayManager,
///   eventVerifier: eventVerifier,
///   eventOutFilters: const [],
///   defaultQueryTimeout: const Duration(seconds: 10),
/// );
/// final notes = await requests.query(filter: Filter(kinds: [1])).future;
/// ```
library;

export 'src/cache_read.dart';
export 'src/event_filter.dart';
export 'src/fetched_ranges.dart';
export 'src/jit_engine/jit_engine.dart';
export 'src/jit_engine/jit_engine_relay_connectivity_data.dart';
export 'src/ndk_request.dart';
export 'src/network_engine.dart';
export 'src/relay_sets_engine.dart';
export 'src/request_response.dart';
export 'src/requests.dart';
export 'src/tag_count_event_filter.dart';
