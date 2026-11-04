import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../../../config/request_defaults.dart';
import '../../../config/rx_defaults.dart';
import '../../../shared/helpers/bounded_lru_set.dart';
import '../../../shared/helpers/relay_helper.dart';
import '../../../shared/logger/logger.dart';
import '../../../shared/nips/nip01/event_kind_classification.dart';
import '../../../shared/nips/nip01/helpers.dart';
import '../../entities/account.dart';
import '../../entities/event_filter.dart';
import '../../entities/filter.dart';
import '../../entities/global_state.dart';
import '../../entities/ndk_request.dart';
import '../../entities/nip_01_event.dart';
import '../../entities/auth_policy.dart';
import '../../entities/relay_set.dart';
import '../../entities/relay_request_outcome.dart';
import '../../entities/request_response.dart';
import '../../repositories/cache_manager.dart';
import '../../repositories/event_verifier.dart';
import '../cache_read/cache_read.dart';
import '../fetched_ranges/fetched_ranges.dart';
import '../engines/network_engine.dart';
import '../relay_manager.dart';
import '../relay_reqs/relay_reqs.dart';
import '../stream_response_cleaner/stream_response_cleaner.dart';
import 'concurrency_check.dart';

/// Internal state for tracking pagination progress on a single relay
class _RelayPaginationState {
  int? oldestTimestamp;
  int? currentUntil;
  bool exhausted = false;
}

/// One network request, served to every identical request that joined it.
class _SharedRequest {
  final RelayReq relayReq;
  final String? hash;

  /// cache and network events, each once, past the event out filters
  final ReplaySubject<Nip01Event> events = ReplaySubject<Nip01Event>(
    maxSize: RX_REPLAYSUBJECT_MAX_EVENTS,
  );
  final Set<_Caller> callers = {};

  _SharedRequest(this.relayReq, this.hash);
}

/// A request served by a [_SharedRequest], with a stream of its own so it can
/// be closed without ending the others.
class _Caller {
  final String id;
  final _SharedRequest shared;
  final ReplaySubject<Nip01Event> events = ReplaySubject<Nip01Event>(
    maxSize: RX_REPLAYSUBJECT_MAX_EVENTS,
  );
  late final StreamSubscription<Nip01Event> _subscription;

  _Caller(this.id, this.shared) {
    _subscription = shared.events.listen(events.add, onDone: events.close);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await events.close();
  }
}

/// A class that handles low-level Nostr network requests and subscriptions.
class Requests {
  static const int _persistedEventIdsMaxSize = 20000;

  /// NIP-01 caps subscription ids at 64 chars. [name] only reaches the relay
  /// in [_debugMode], so production ids do not fingerprint NDK (#716).
  String _requestId(String name) {
    if (!_debugMode) return Helpers.getSecureRandomHex(16);
    final prefix = name.length > 32 ? name.substring(0, 32) : name;
    return '$prefix-${Helpers.getSecureRandomHex(8)}';
  }

  static void _checkExplicitId(String? id) {
    if (id == null) return;
    if (id.isNotEmpty && id.length <= 64) return;
    throw ArgumentError.value(id, 'id', 'must be 1 to 64 characters long');
  }

  final GlobalState _globalState;
  final CacheRead _cacheRead;
  final CacheManager _cacheManager;
  final NetworkEngine _engine;
  final RelayManager _relayManager;
  final RelayReqs _relayReqs;
  final List<EventFilter> _eventOutFilters;
  final Duration _defaultQueryTimeout;
  final bool _debugMode;
  FetchedRanges? _fetchedRanges;

  final ConcurrencyCheck _concurrency = ConcurrencyCheck();
  final Map<String, _SharedRequest> _sharedByHash = {};
  final Map<String, _Caller> _callers = {};

  /// Creates a new [Requests] instance
  ///
  /// [globalState] The global state of the application \
  /// [cacheRead] The cache reader for retrieving cached events \
  /// [cacheManager] The cache used to persist network-delivered events \
  /// [networkEngine] The engine for handling network requests \
  /// [eventVerifier] The verifier for validating Nostr events \
  /// [relayReqs] The REQs this builds on, by default its own ones
  Requests({
    required GlobalState globalState,
    required CacheRead cacheRead,
    required CacheManager cacheManager,
    required NetworkEngine networkEngine,
    required RelayManager relayManager,
    required EventVerifier eventVerifier,
    required List<EventFilter> eventOutFilters,
    required Duration defaultQueryTimeout,
    bool debugMode = false,
    RelayReqs? relayReqs,
  }) : _relayReqs =
           relayReqs ??
           RelayReqs(relayManager: relayManager, eventVerifier: eventVerifier),
       _engine = networkEngine,
       _relayManager = relayManager,
       _cacheManager = cacheManager,
       _cacheRead = cacheRead,
       _globalState = globalState,
       _eventOutFilters = eventOutFilters,
       _defaultQueryTimeout = defaultQueryTimeout,
       _debugMode = debugMode;

  /// Clears signature-verification reuse state owned by this NDK instance.
  void clearVerifiedEventCache() => _relayReqs.clearVerifiedEventCache();

  Stream<Nip01Event> _prepareNetworkStream(
    Stream<Nip01Event> verifiedNetworkStream, {
    required bool writeToCache,
  }) {
    if (!writeToCache) {
      return verifiedNetworkStream;
    }

    final persistedEventIds = BoundedLruSet<String>(
      maxSize: _persistedEventIdsMaxSize,
    );
    final persistenceInFlight = <String, Future<void>>{};

    return verifiedNetworkStream
        .flatMap(
          (event) => Stream.fromFuture(
            _persistAndFilterVisibleNetworkEvent(
              event,
              persistedEventIds: persistedEventIds,
              persistenceInFlight: persistenceInFlight,
            ),
          ),
        )
        .whereType<Nip01Event>()
        .shareReplay(maxSize: 1);
  }

  Future<Nip01Event?> _persistAndFilterVisibleNetworkEvent(
    Nip01Event event, {
    required BoundedLruSet<String> persistedEventIds,
    required Map<String, Future<void>> persistenceInFlight,
  }) async {
    // Ephemeral events (NIP-01 kinds 20000-29999) are non-persistent by
    // definition. They must not be written to cache — relays don't store them
    // either. Inbound events flow through to the subscriber but are not
    // persisted, preventing unbounded cache growth. Locally-created ephemeral
    // events (broadcast / pending-delivery) bypass this path and remain cached
    // for local-first delivery and retry.
    if (EventKindClassification.isEphemeralKind(event.kind)) {
      return event;
    }

    final existingPersistence = persistenceInFlight[event.id];
    if (existingPersistence != null) {
      await existingPersistence;
    } else if (persistedEventIds.add(event.id)) {
      final persistence = Future<void>.sync(() async {
        await _cacheManager.saveEventIfAbsent(event);
      });
      persistenceInFlight[event.id] = persistence;
      try {
        await persistence;
      } catch (_) {
        persistedEventIds.remove(event.id);
        rethrow;
      } finally {
        if (identical(persistenceInFlight[event.id], persistence)) {
          persistenceInFlight.remove(event.id);
        }
      }
    }
    if (event.sources.isNotEmpty) {
      await _cacheManager.addEventSources(
        eventId: event.id,
        relayUrls: event.sources.toSet(),
      );
    }

    if (event.kind == 5) {
      return event;
    }

    final visible = await _cacheManager.loadEvents(ids: [event.id], limit: 1);

    return visible.any((candidate) => candidate.id == event.id) ? event : null;
  }

  /// Set the fetched ranges tracker for automatic range recording
  set fetchedRanges(FetchedRanges? fetchedRanges) =>
      _fetchedRanges = fetchedRanges;

  /// Performs a low-level Nostr query
  ///
  /// [filter] The filter to apply to the query \
  /// [filters] @deprecated A list of filters to apply to the query. Use [filter] instead \
  /// [name] An optional name for logging, also prefixed to the ID (first 32 characters) when [NdkConfig.debugMode] is on \
  /// [id] An optional ID sent as the NIP-01 subscription id (1 to 64 characters), overriding name; not allowed with [paginate] \
  /// [relaySet] An optional set of relays to query \
  /// [cacheRead] Whether to read from cache \
  /// [cacheWrite] Whether to write results to cache \
  /// [timeout] An optional timeout in seconds for the query if not set ndk default will be used \
  /// [explicitRelays] A list of specific relays to use, bypassing inbox/outbox \
  /// [desiredCoverage] The number of relays per pubkey to query, default: 2 \
  /// [timeoutCallbackUserFacing] A user facing timeout callback, this callback should be given to the lib user \
  /// [timeoutCallback] An internal timeout callback, this callback should be used for internal error handling \
  /// [auth] which identity this query may be attributed to on relays (NIP-42), see [AuthPolicy] \
  /// [authenticateAs] @deprecated use [auth] instead; [auth] wins when both are given \
  /// [paginate] If true, automatically paginates backwards through time to fetch all events in the range \
  ///
  /// Returns an [NdkResponse] containing the query result stream, future
  NdkResponse query({
    Filter? filter,
    @Deprecated(
      'Use filter instead. Multiple filters support will be removed in a future version.',
    )
    List<Filter>? filters,
    String name = '',
    String? id,
    RelaySet? relaySet,
    bool cacheRead = true,
    bool cacheWrite = true,
    Duration? timeout,
    Function()? timeoutCallbackUserFacing,
    Function()? timeoutCallback,
    Iterable<String>? explicitRelays,
    int? desiredCoverage,
    AuthPolicy? auth,
    @Deprecated(
      'Use auth: AuthPolicy.allow(account) instead. authenticateAs will be removed in a future version.',
    )
    List<Account>? authenticateAs,
    bool paginate = false,
  }) {
    if (filter == null && (filters == null || filters.isEmpty)) {
      throw ArgumentError('Either filter or filters must be provided');
    }
    _checkExplicitId(id);
    if (id != null && paginate) {
      // each page sends its own REQ, so there is no single id to give it
      throw ArgumentError('id cannot be combined with paginate');
    }
    final effectiveFilters = filter != null ? [filter] : filters!;
    final effectiveAuth =
        auth ?? AuthPolicy.fromDeprecatedAccounts(authenticateAs);
    timeout ??= _defaultQueryTimeout;

    if (paginate) {
      return _paginatedQuery(
        filter: effectiveFilters.first,
        name: name,
        relaySet: relaySet,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite,
        timeout: timeout,
        timeoutCallbackUserFacing: timeoutCallbackUserFacing,
        timeoutCallback: timeoutCallback,
        explicitRelays: explicitRelays,
        desiredCoverage: desiredCoverage,
        auth: effectiveAuth,
      );
    }

    return requestNostrEvent(
      NdkRequest.query(
        id ?? _requestId(name),
        name: name,
        filters: effectiveFilters.map((e) => e.clone()).toList(),
        relaySet: relaySet,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite,
        timeoutDuration: timeout,
        timeoutCallbackUserFacing: timeoutCallbackUserFacing,
        timeoutCallback: timeoutCallback,
        explicitRelays: explicitRelays,
        desiredCoverage:
            desiredCoverage ?? RequestDefaults.DEFAULT_BEST_RELAYS_MIN_COUNT,
        auth: effectiveAuth,
      ),
    );
  }

  /// Creates a low-level Nostr subscription
  ///
  /// [filter] The filter to apply to the subscription \
  /// [filters] @deprecated A list of filters to apply to the subscription. Use [filter] instead \
  /// [name] An optional name for logging, also prefixed to the ID (first 32 characters) when [NdkConfig.debugMode] is on \
  /// [id] An optional ID sent as the NIP-01 subscription id (1 to 64 characters), overriding name \
  /// [relaySet] An optional set of relays to subscribe to \
  /// [cacheRead] Whether to read from cache \
  /// [cacheWrite] Whether to write results to cache \
  /// [explicitRelays] A list of specific relays to use, bypassing inbox/outbox \
  /// [desiredCoverage] The number of relays per pubkey to subscribe to, default: 2 \
  /// [auth] which identity this subscription may be attributed to on relays (NIP-42), see [AuthPolicy] \
  /// [authenticateAs] @deprecated use [auth] instead; [auth] wins when both are given \
  ///
  /// Returns an [NdkResponse] containing the subscription results as stream
  NdkResponse subscription({
    Filter? filter,
    @Deprecated(
      'Use filter instead. Multiple filters support will be removed in a future version.',
    )
    List<Filter>? filters,
    String name = '',
    String? id,
    RelaySet? relaySet,
    bool cacheRead = false,
    bool cacheWrite = false,
    Iterable<String>? explicitRelays,
    int? desiredCoverage,
    AuthPolicy? auth,
    @Deprecated(
      'Use auth: AuthPolicy.allow(account) instead. authenticateAs will be removed in a future version.',
    )
    List<Account>? authenticateAs,
  }) {
    if (filter == null && (filters == null || filters.isEmpty)) {
      throw ArgumentError('Either filter or filters must be provided');
    }
    _checkExplicitId(id);
    final effectiveFilters = filter != null ? [filter] : filters!;
    final effectiveAuth =
        auth ?? AuthPolicy.fromDeprecatedAccounts(authenticateAs);
    return requestNostrEvent(
      NdkRequest.subscription(
        id ?? _requestId(name),
        name: name,
        filters: effectiveFilters.map((e) => e.clone()).toList(),
        relaySet: relaySet,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite,
        explicitRelays: explicitRelays,
        desiredCoverage:
            desiredCoverage ?? RequestDefaults.DEFAULT_BEST_RELAYS_MIN_COUNT,
        auth: effectiveAuth,
      ),
    );
  }

  /// Closes a Nostr network subscription
  ///
  /// A request that shares its network request with identical ones only stops
  /// its own stream: the REQ is closed once none of them is left.
  Future<void> closeSubscription(String subId, {String debugLabel = ""}) async {
    final caller = _callers[subId];
    if (caller != null) return _release(caller);

    final state = _globalState.inFlightRequests[subId];
    if (state == null) {
      Logger.log.w(
        () =>
            "no relay urls found for subscription $subId, cannot close :: debug: $debugLabel",
      );
      return;
    }

    await _relayManager.closeRequest(state);
  }

  /// Close all subscriptions, and the REQs opened outside of [Requests]
  Future<void> closeAllSubscription() async {
    await Future.wait([
      for (final caller in _callers.values.toList()) _release(caller),
    ]);
    await Future.wait([
      for (final state in _globalState.inFlightRequests.values.toList())
        _relayManager.closeRequest(state),
    ]);
  }

  Future<void> _release(_Caller caller) async {
    _forget(caller);
    await caller.close();
    final shared = caller.shared;
    if (shared.callers.isNotEmpty) return;
    if (identical(_sharedByHash[shared.hash], shared)) {
      _sharedByHash.remove(shared.hash);
    }
    await shared.relayReq.close();
  }

  void _forget(_Caller caller) {
    if (identical(_callers[caller.id], caller)) _callers.remove(caller.id);
    caller.shared.callers.remove(caller);
  }

  /// Performs a low-level Nostr event request
  ///
  /// This method should be used only if the prebuilt use cases and
  /// [query] or [subscription] methods do not meet your needs
  ///
  /// [request] The [NdkRequest] object containing request parameters
  ///
  /// Returns an [NdkResponse] containing the request results
  NdkResponse requestNostrEvent(NdkRequest request) {
    if (_callers.containsKey(request.id)) {
      throw StateError('a request with id ${request.id} is already in flight');
    }
    final hash = request.cacheRead ? _concurrency.hash(request) : null;
    final shared =
        (hash == null ? null : _sharedByHash[hash]) ?? _open(request, hash);

    final caller = _Caller(request.id, shared);
    shared.callers.add(caller);
    _callers[caller.id] = caller;
    caller.events.done.then((_) => _forget(caller));

    return NdkResponse(
      caller.id,
      caller.events.stream,
      relayOutcomes: () => shared.relayReq.outcomes,
      relayOutcomesStream: () => shared.relayReq.outcomesStream,
      relayOutcomesDone: caller.events.done.then(
        (_) => shared.relayReq.outcomes,
      ),
    );
  }

  /// Opens the network request behind [request], and the cache read and
  /// cache write around it.
  _SharedRequest _open(NdkRequest request, String? hash) {
    final relayReq = _relayReqs.req(
      id: request.id,
      name: request.name,
      closeOnEose: request.closeOnEOSE,
      auth: request.auth,
      timeout: request.timeoutDuration,
    );
    final shared = _SharedRequest(relayReq, hash);
    if (hash != null) _sharedByHash[hash] = shared;

    final cacheEvents = StreamController<Nip01Event>();
    final sentFilters = <String, List<Filter>>{};

    final networkEvents = _prepareNetworkStream(
      relayReq.events,
      writeToCache: request.cacheWrite,
    );

    // only the oldest timestamp per relay is needed, buffering the events
    // themselves would grow unbounded on long-lived subscriptions
    final oldestNetworkEventByRelay = <String, int>{};
    final trackedNetworkEvents = _fetchedRanges == null
        ? networkEvents
        : networkEvents.map((event) {
            for (final source in event.sources) {
              final oldest = oldestNetworkEventByRelay[source];
              if (oldest == null || event.createdAt < oldest) {
                oldestNetworkEventByRelay[source] = event.createdAt;
              }
            }
            return event;
          });

    StreamResponseCleaner(
      inputStreams: [trackedNetworkEvents, cacheEvents.stream],
      trackingSet: {},
      outController: shared.events,
      eventOutFilters: _eventOutFilters,
    )();

    // once the network stream is drained, not merely closed: events still
    // being persisted would be missing from the ranges
    shared.events.done.then((_) {
      if (hash != null && identical(_sharedByHash[hash], shared)) {
        _sharedByHash.remove(hash);
      }
      _recordFetchedRanges(
        relayReq.outcomes,
        sentFilters,
        oldestNetworkEventByRelay,
      );
      Logger.log.d(() => "req done: ${relayReq.id}");
    });

    relayReq.done.then((_) {
      if (!relayReq.timedOut) return;
      request.timeoutCallback?.call();
      request.timeoutCallbackUserFacing?.call();
    });

    _resolve(request, relayReq, cacheEvents, sentFilters).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      Logger.log.e(
        () => "${relayReq.id} failed",
        error: error,
        stackTrace: stackTrace,
      );
      if (!cacheEvents.isClosed) unawaited(cacheEvents.close());
      unawaited(relayReq.close());
    });
    return shared;
  }

  /// Serves what it can from the cache, then sends the rest to the relays:
  /// the explicit ones, or those the engine picks.
  Future<void> _resolve(
    NdkRequest request,
    RelayReq relayReq,
    StreamController<Nip01Event> cacheEvents,
    Map<String, List<Filter>> sentFilters,
  ) async {
    var filters = request.filters;
    if (request.cacheRead) {
      try {
        filters = await _cacheRead.resolveUnresolvedFilters(
          filters: filters,
          outController: cacheEvents,
        );
      } catch (error, stackTrace) {
        Logger.log.w(
          () => "${relayReq.id} could not read the cache, asking the relays",
          error: error,
          stackTrace: stackTrace,
        );
        if (!cacheEvents.isClosed) unawaited(cacheEvents.close());
      }
    } else {
      unawaited(cacheEvents.close());
    }

    // a request that requires an identity nobody can sign for has no
    // connection to go out on, and its timeout would only delay the same
    // empty answer. The cache already had its say above
    final auth = request.auth;
    if (auth is AuthPolicyRequire && !auth.account.signer.canSign()) {
      Logger.log.w(
        () =>
            "${relayReq.id} requires ${auth.account.pubkey}, which cannot sign",
      );
      relayReq.seal();
      return;
    }
    if (filters.isEmpty) {
      relayReq.seal();
      return;
    }

    void send(String url, List<Filter> relayFilters) {
      if (relayReq.send(url, relayFilters)) {
        sentFilters[cleanRelayUrl(url) ?? url] = relayFilters;
      }
    }

    final explicitRelays = request.explicitRelays;
    if (explicitRelays != null && explicitRelays.isNotEmpty) {
      // explicit relays bypass outbox routing, each gets every filter
      final sliced = [
        for (final filter in filters) ...RelaySet.sliceFilterAuthors(filter),
      ];
      for (final url in cleanRelayUrls(explicitRelays.toList()).toSet()) {
        send(url, List.of(sliced));
      }
      relayReq.seal();
      return;
    }

    try {
      await _engine.route(
        filters,
        send,
        relaySet: request.relaySet,
        desiredCoverage: request.desiredCoverage,
      );
    } catch (error, stackTrace) {
      // the relays handed over so far still serve the request
      Logger.log.e(
        () => "routing ${relayReq.id} failed",
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      relayReq.seal();
    }
  }

  /// Performs a paginated query that fetches all events in a time range
  /// by making multiple requests per relay, each time adjusting the `until` parameter
  /// to fetch older events until `since` is reached or no more events are returned.
  /// Pagination is done independently per relay to avoid skipping events.
  NdkResponse _paginatedQuery({
    required Filter filter,
    String name = '',
    RelaySet? relaySet,
    bool cacheRead = true,
    bool cacheWrite = true,
    Duration? timeout,
    Function()? timeoutCallbackUserFacing,
    Function()? timeoutCallback,
    Iterable<String>? explicitRelays,
    int? desiredCoverage,
    AuthPolicy? auth,
  }) {
    final requestId = _requestId(name);
    final aggregatedController = ReplaySubject<Nip01Event>();
    final seenEventIds = <String>{};

    // a relay is paginated by its own sequence of requests, so what it ended
    // with is what its last page ended with
    final relayOutcomes = <String, RelayRequestOutcome>{};
    final relayOutcomesDone = Completer<Map<String, RelayRequestOutcome>>();
    final relayOutcomesSubject =
        BehaviorSubject<Map<String, RelayRequestOutcome>>.seeded(const {});

    void mergeRelayOutcomes(Map<String, RelayRequestOutcome> page) {
      relayOutcomes.addAll(page);
      if (!relayOutcomesSubject.isClosed) {
        relayOutcomesSubject.add(Map.unmodifiable(relayOutcomes));
      }
    }

    /// Awaits a page, merging what its relays answer while it is still running
    /// so the aggregated stream reports a pending relay instead of only the
    /// pages that ended.
    Future<List<Nip01Event>> awaitPage(NdkResponse page) async {
      final outcomes = page.relayOutcomesStream.listen(mergeRelayOutcomes);
      try {
        return await page.future;
      } finally {
        await outcomes.cancel();
        mergeRelayOutcomes(page.relayOutcomes);
      }
    }

    Future<void> paginate() async {
      final since = filter.since;

      // First request to discover relays and get initial events
      final initialResponse = requestNostrEvent(
        NdkRequest.query(
          _requestId(name),
          name: name,
          filters: [filter.clone()],
          relaySet: relaySet,
          cacheRead: cacheRead,
          cacheWrite: cacheWrite,
          timeoutDuration: timeout,
          timeoutCallbackUserFacing: timeoutCallbackUserFacing,
          timeoutCallback: timeoutCallback,
          explicitRelays: explicitRelays,
          desiredCoverage:
              desiredCoverage ?? RequestDefaults.DEFAULT_BEST_RELAYS_MIN_COUNT,
          auth: auth,
        ),
      );

      final initialEvents = await awaitPage(initialResponse);

      // Emit initial events and discover relays
      final relayState = <String, _RelayPaginationState>{};

      for (final event in initialEvents) {
        if (!seenEventIds.contains(event.id)) {
          seenEventIds.add(event.id);
          aggregatedController.add(event);
        }

        // Track oldest timestamp per relay
        for (final relay in event.sources) {
          final state = relayState.putIfAbsent(
            relay,
            () => _RelayPaginationState(),
          );
          if (state.oldestTimestamp == null ||
              event.createdAt < state.oldestTimestamp!) {
            state.oldestTimestamp = event.createdAt;
          }
        }
      }

      // If no events or no relays discovered, we're done
      if (initialEvents.isEmpty || relayState.isEmpty) {
        await aggregatedController.close();
        return;
      }

      // Initialize relay states
      for (final entry in relayState.entries) {
        final state = entry.value;
        if (state.oldestTimestamp != null) {
          state.currentUntil = state.oldestTimestamp! - 1;
          // Check if already reached since
          if (since != null && state.oldestTimestamp! <= since) {
            state.exhausted = true;
          }
        } else {
          state.exhausted = true;
        }
      }

      // Paginate each relay independently
      while (relayState.values.any((s) => !s.exhausted)) {
        // Get active relays
        final activeRelays = relayState.entries
            .where((e) => !e.value.exhausted)
            .map((e) => e.key)
            .toList();

        // Make parallel requests to all active relays
        final futures = activeRelays.map((relay) async {
          final state = relayState[relay]!;
          final pageFilter = filter.clone();
          pageFilter.until = state.currentUntil;

          final response = requestNostrEvent(
            NdkRequest.query(
              _requestId(name),
              name: name,
              filters: [pageFilter],
              cacheRead: false, // Don't read from cache for subsequent pages
              cacheWrite: cacheWrite,
              timeoutDuration: timeout,
              timeoutCallbackUserFacing: timeoutCallbackUserFacing,
              timeoutCallback: timeoutCallback,
              explicitRelays: [relay],
              desiredCoverage: 1,
              auth: auth,
            ),
          );

          final pageEvents = await awaitPage(response);
          return MapEntry(relay, pageEvents);
        });

        final results = await Future.wait(futures);

        // Process results
        for (final result in results) {
          final relay = result.key;
          final pageEvents = result.value;
          final state = relayState[relay]!;

          int? oldestTimestamp;
          for (final event in pageEvents) {
            if (!seenEventIds.contains(event.id)) {
              seenEventIds.add(event.id);
              aggregatedController.add(event);
            }
            // Track oldest timestamp for this relay
            if (oldestTimestamp == null || event.createdAt < oldestTimestamp) {
              oldestTimestamp = event.createdAt;
            }
          }

          if (pageEvents.isEmpty || oldestTimestamp == null) {
            state.exhausted = true;
          } else {
            state.currentUntil = oldestTimestamp - 1;
            // Check if reached since
            if (since != null && oldestTimestamp <= since) {
              state.exhausted = true;
            }
          }
        }
      }

      await aggregatedController.close();
    }

    // Start pagination asynchronously
    paginate().whenComplete(() {
      relayOutcomesDone.complete(Map.of(relayOutcomes));
      relayOutcomesSubject.close();
    });

    return NdkResponse(
      requestId,
      aggregatedController.stream,
      relayOutcomes: () => Map.of(relayOutcomes),
      relayOutcomesStream: () => relayOutcomesSubject.stream,
      relayOutcomesDone: relayOutcomesDone.future,
    );
  }

  /// Records fetched ranges for each relay that received EOSE
  /// - If events received: coverage starts at the oldest event received
  /// - If no events: use the filter bounds (0 to now when unbounded)
  ///
  /// [oldestEventByRelay] must only reflect events received from relays during
  /// this request. Cache hits would make the recorded range claim coverage the
  /// relay never actually served.
  void _recordFetchedRanges(
    Map<String, RelayRequestOutcome> outcomes,
    Map<String, List<Filter>> sentFilters,
    Map<String, int> oldestEventByRelay,
  ) {
    if (_fetchedRanges == null) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final MapEntry(key: relayUrl, value: filters) in sentFilters.entries) {
      if (outcomes[relayUrl]?.status != RelayRequestStatus.eose) continue;

      final oldestEvent = oldestEventByRelay[relayUrl];

      // Record fetched range for each filter sent to this relay
      for (final filter in filters) {
        int since = filter.since ?? 0;
        final int until = filter.until ?? now;

        if (oldestEvent != null) {
          // A relay can cap a response below the requested limit, or with no
          // limit in the filter at all (NIP-11 max_limit, which we don't read),
          // so a full response is indistinguishable from a truncated one. Only
          // claim coverage down to the oldest event received.
          since = oldestEvent;
        }

        _fetchedRanges!.addRange(
          filter: filter,
          relayUrl: relayUrl,
          since: since,
          until: until,
        );
      }
    }
  }
}
