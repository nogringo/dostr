import 'dart:async';

import 'package:rxdart/rxdart.dart';

import 'package:ndk/config/request_defaults.dart';
import 'package:ndk_core/config/rx_defaults.dart';
import '../../../shared/helpers/bounded_lru_set.dart';
import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'package:ndk_core/shared/logger/logger.dart';
import '../../../shared/nips/nip01/event_kind_classification.dart';
import '../../../shared/nips/nip01/helpers.dart';
import '../../entities/event_filter.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import '../../entities/ndk_request.dart';
import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import 'package:ndk_core/domain_layer/entities/auth_policy.dart';
import '../../entities/relay_set.dart';
import 'package:ndk_core/domain_layer/entities/relay_req_event.dart';
import 'package:ndk_core/domain_layer/entities/relay_request_outcome.dart';
import '../../entities/request_response.dart';
import '../../repositories/cache_manager.dart';
import 'package:ndk_core/domain_layer/repositories/event_verifier.dart';
import '../cache_read/cache_read.dart';
import '../fetched_ranges/fetched_ranges.dart';
import '../engines/network_engine.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import '../stream_response_cleaner/stream_response_cleaner.dart';
import 'concurrency_check.dart';

/// How far a paginated query got on a single relay
class _RelayPaginationState {
  /// ids this relay returned, so a page is only progress if it brought new ones
  final Set<String> seen = {};
  int? until;
  bool stalled = false;
}

/// A paginated query in flight, so it can be closed like any request
class _Pagination {
  final String id;
  final ReplaySubject<Nip01Event> events = ReplaySubject<Nip01Event>();
  final Set<String> pageIds = {};
  bool cancelled = false;

  _Pagination(this.id);
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

  final CacheRead _cacheRead;
  final CacheManager _cacheManager;
  final NetworkEngine _engine;
  final RelayReqs _relayReqs;
  final List<EventFilter> _eventOutFilters;
  final Duration _defaultQueryTimeout;
  final bool _debugMode;
  FetchedRanges? _fetchedRanges;

  final ConcurrencyCheck _concurrency = ConcurrencyCheck();
  final Map<String, _SharedRequest> _sharedByHash = {};
  final Map<String, _Caller> _callers = {};
  final Map<String, _Pagination> _paginations = {};

  /// Creates a new [Requests] instance
  ///
  /// [cacheRead] The cache reader for retrieving cached events \
  /// [cacheManager] The cache used to persist network-delivered events \
  /// [networkEngine] The engine for handling network requests \
  /// [eventVerifier] The verifier for validating Nostr events \
  /// [relayReqs] The REQs this builds on, by default its own ones
  Requests({
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
       _cacheManager = cacheManager,
       _cacheRead = cacheRead,
       _eventOutFilters = eventOutFilters,
       _defaultQueryTimeout = defaultQueryTimeout,
       _debugMode = debugMode;

  /// Clears signature-verification reuse state owned by this NDK instance.
  void clearVerifiedEventCache() => _relayReqs.clearVerifiedEventCache();

  Stream<RelayReqEvent> _prepareNetworkStream(
    Stream<RelayReqEvent> verifiedNetworkStream, {
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
          (received) => Stream.fromFuture(
            _persistAndFilterVisibleNetworkEvent(
              received,
              persistedEventIds: persistedEventIds,
              persistenceInFlight: persistenceInFlight,
            ),
          ),
        )
        .whereType<RelayReqEvent>()
        .shareReplay(maxSize: 1);
  }

  Future<RelayReqEvent?> _persistAndFilterVisibleNetworkEvent(
    RelayReqEvent received, {
    required BoundedLruSet<String> persistedEventIds,
    required Map<String, Future<void>> persistenceInFlight,
  }) async {
    final event = received.event;
    // Ephemeral events (NIP-01 kinds 20000-29999) are non-persistent by
    // definition. They must not be written to cache — relays don't store them
    // either. Inbound events flow through to the subscriber but are not
    // persisted, preventing unbounded cache growth. Locally-created ephemeral
    // events (broadcast / pending-delivery) bypass this path and remain cached
    // for local-first delivery and retry.
    if (EventKindClassification.isEphemeralKind(event.kind)) {
      return received;
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
    await _cacheManager.addEventSource(
      eventId: event.id,
      relayUrl: received.relayUrl,
    );

    if (event.kind == 5) {
      return received;
    }

    final visible = await _cacheManager.loadEvents(ids: [event.id], limit: 1);

    return visible.any((candidate) => candidate.id == event.id)
        ? received
        : null;
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
        auth: auth,
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
        auth: auth,
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
  }) {
    if (filter == null && (filters == null || filters.isEmpty)) {
      throw ArgumentError('Either filter or filters must be provided');
    }
    _checkExplicitId(id);
    final effectiveFilters = filter != null ? [filter] : filters!;
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
        auth: auth,
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
    final pagination = _paginations[subId];
    if (pagination != null) return _cancel(pagination);

    if (!await _relayReqs.close(subId)) {
      Logger.log.w(
        () =>
            "no relay urls found for subscription $subId, cannot close :: debug: $debugLabel",
      );
    }
  }

  /// Close all subscriptions, and the REQs opened outside of [Requests]
  Future<void> closeAllSubscription() async {
    await Future.wait([
      for (final pagination in _paginations.values.toList())
        _cancel(pagination),
    ]);
    await Future.wait([
      for (final caller in _callers.values.toList()) _release(caller),
    ]);
    await _relayReqs.closeAll();
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

  Future<void> _cancel(_Pagination pagination) async {
    pagination.cancelled = true;
    if (identical(_paginations[pagination.id], pagination)) {
      _paginations.remove(pagination.id);
    }
    await Future.wait([
      for (final pageId in pagination.pageIds.toList())
        closeSubscription(pageId),
    ]);
    await pagination.events.close();
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
    final trackedNetworkEvents = networkEvents.map((received) {
      final event = received.event;
      if (_fetchedRanges != null) {
        final oldest = oldestNetworkEventByRelay[received.relayUrl];
        if (oldest == null || event.createdAt < oldest) {
          oldestNetworkEventByRelay[received.relayUrl] = event.createdAt;
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
      if (relayReq.closeOnEose) {
        _recordFetchedRanges(
          relayReq.outcomes,
          sentFilters,
          oldestNetworkEventByRelay,
        );
      }
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
    var filters = [
      for (final filter in request.filters)
        if (!filter.matchesNothing) filter,
    ];
    if (filters.isEmpty) {
      unawaited(cacheEvents.close());
      relayReq.seal();
      return;
    }
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

    try {
      await _dispatch(
        filters,
        send,
        explicitRelays: request.explicitRelays,
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

  /// Hands [filters] to the relays they go to: the [explicitRelays], or those
  /// the engine picks.
  Future<void> _dispatch(
    List<Filter> filters,
    RelaySend send, {
    Iterable<String>? explicitRelays,
    RelaySet? relaySet,
    required int desiredCoverage,
  }) async {
    if (explicitRelays != null && explicitRelays.isNotEmpty) {
      // explicit relays bypass outbox routing, each gets every filter
      final sliced = [
        for (final filter in filters) ...RelaySet.sliceFilterAuthors(filter),
      ];
      for (final url in cleanRelayUrls(explicitRelays.toList()).toSet()) {
        send(url, List.of(sliced));
      }
      return;
    }
    await _engine.route(
      filters,
      send,
      relaySet: relaySet,
      desiredCoverage: desiredCoverage,
    );
  }

  bool _passesEventOutFilters(Nip01Event event) =>
      _eventOutFilters.every((filter) => filter.filter(event));

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
    final pagination = _Pagination(_requestId(name));
    _paginations[pagination.id] = pagination;
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

    // once for the whole query, however many of its pages time out
    var timedOut = false;
    void onPageTimeout() {
      if (timedOut) return;
      timedOut = true;
      timeoutCallback?.call();
      timeoutCallbackUserFacing?.call();
    }

    void emit(Nip01Event event) {
      if (pagination.events.isClosed || !seenEventIds.add(event.id)) return;
      pagination.events.add(event);
    }

    /// Pages backwards through [url] alone, so a page only answers for the
    /// relay it was sent to.
    Future<void> paginateRelay(String url, List<Filter> relayFilters) async {
      final progress = _RelayPaginationState();
      while (!pagination.cancelled) {
        final page = requestNostrEvent(
          NdkRequest.query(
            _requestId(name),
            name: name,
            filters: [
              for (final relayFilter in relayFilters)
                relayFilter.clone()
                  ..until = progress.until ?? relayFilter.until,
            ],
            cacheRead: false,
            cacheWrite: cacheWrite,
            timeoutDuration: timeout,
            timeoutCallback: onPageTimeout,
            explicitRelays: [url],
            desiredCoverage: 1,
            auth: auth,
          ),
        );
        pagination.pageIds.add(page.requestId);
        final List<Nip01Event> pageEvents;
        try {
          pageEvents = await awaitPage(page);
        } finally {
          pagination.pageIds.remove(page.requestId);
        }
        if (pageEvents.isEmpty) return;

        var fresh = false;
        var oldest = pageEvents.first.createdAt;
        for (final event in pageEvents) {
          emit(event);
          fresh = progress.seen.add(event.id) || fresh;
          if (event.createdAt < oldest) oldest = event.createdAt;
        }

        if (fresh) {
          // inclusive: the events of the oldest timestamp may not all have
          // fit in this page
          progress.until = oldest;
          progress.stalled = false;
        } else if (progress.stalled) {
          return;
        } else {
          // more events share that timestamp than a page holds, the ones the
          // relay never returned cannot be reached without skipping it
          progress.until = oldest - 1;
          progress.stalled = true;
        }
      }
    }

    Future<void> paginate() async {
      if (filter.matchesNothing) return;
      var filters = [filter.clone()];
      if (cacheRead) {
        final cached = StreamController<Nip01Event>();
        final emitted = cached.stream
            .where(_passesEventOutFilters)
            .forEach(emit);
        try {
          filters = await _cacheRead.resolveUnresolvedFilters(
            filters: filters,
            outController: cached,
          );
        } catch (error, stackTrace) {
          Logger.log.w(
            () =>
                "${pagination.id} could not read the cache, asking the relays",
            error: error,
            stackTrace: stackTrace,
          );
          if (!cached.isClosed) unawaited(cached.close());
        }
        await emitted;
      }
      if (filters.isEmpty || pagination.cancelled) return;
      if (auth is AuthPolicyRequire && !auth.account.signer.canSign()) {
        Logger.log.w(
          () =>
              "${pagination.id} requires ${auth.account.pubkey}, which cannot sign",
        );
        return;
      }

      final relays = <Future<void>>[];
      var over = false;
      await _dispatch(
        filters,
        (url, relayFilters) {
          // a relay the engine hands over once every other one is done
          // would start the query over on its own
          if (over || pagination.cancelled) return;
          relays.add(paginateRelay(url, relayFilters));
        },
        explicitRelays: explicitRelays,
        relaySet: relaySet,
        desiredCoverage:
            desiredCoverage ?? RequestDefaults.DEFAULT_BEST_RELAYS_MIN_COUNT,
      );
      var awaited = 0;
      while (awaited < relays.length) {
        final running = relays.sublist(awaited);
        awaited = relays.length;
        await Future.wait(running);
      }
      over = true;
    }

    paginate()
        .catchError((Object error, StackTrace stackTrace) {
          Logger.log.e(
            () => "paginated query ${pagination.id} failed",
            error: error,
            stackTrace: stackTrace,
          );
        })
        .whenComplete(() async {
          if (identical(_paginations[pagination.id], pagination)) {
            _paginations.remove(pagination.id);
          }
          await pagination.events.close();
          relayOutcomesDone.complete(Map.of(relayOutcomes));
          await relayOutcomesSubject.close();
        });

    return NdkResponse(
      pagination.id,
      pagination.events.stream,
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
