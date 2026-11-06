import 'dart:async';

import 'package:http/http.dart' as http;

import '../shared/net/user_agent.dart';
import 'package:ndk_http/ndk_http.dart';
import '../data_layer/repositories/cache_manager/cache_manager_replaceable_events.dart';
import '../data_layer/repositories/lnurl_http_impl.dart';
import '../data_layer/repositories/relay_info_http_impl.dart';
import 'package:ndk_core/data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart';
import 'package:ndk_core/domain_layer/entities/relay_connectivity.dart';
import '../domain_layer/repositories/lnurl_transport.dart';
import '../domain_layer/usecases/accounts/accounts.dart';
import '../domain_layer/usecases/broadcast/broadcast.dart';
import '../domain_layer/usecases/blossom_user_server_list/blossom_user_server_list.dart';
import '../domain_layer/usecases/broadcast/broadcast_sender.dart';
import 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
import 'package:ndk_nip46/ndk_nip46.dart';
import '../domain_layer/usecases/cache_eviction/cache_eviction_scheduler.dart';
import '../domain_layer/usecases/cache_read/cache_read.dart';
import '../domain_layer/usecases/connectivity/connectivity.dart';
import '../domain_layer/usecases/decrypted_event_payloads/decrypted_event_payloads.dart';
import '../domain_layer/usecases/decrypted_event_payloads/decrypted_payloads_gift_wrap_cache.dart';
import '../domain_layer/usecases/engines/network_engine.dart';
import '../domain_layer/usecases/fetched_ranges/fetched_ranges.dart';
import '../domain_layer/usecases/follows/follows.dart';
import 'package:ndk_nip59/ndk_nip59.dart';
import '../domain_layer/usecases/jit_engine/jit_engine.dart';
import '../domain_layer/usecases/lists/lists.dart';
import '../domain_layer/usecases/lnurl/lnurl.dart';
import '../domain_layer/usecases/metadatas/metadatas.dart';
import 'package:ndk_nip05/ndk_nip05.dart';
import 'package:ndk_fetchers/ndk_fetchers.dart'
    show BlossomServersFetcher, DmRelaysFetcher, Nip65Fetcher, fetcherUrlListFn;
import 'package:ndk_nip77/ndk_nip77.dart';
import 'package:ndk_url_set/ndk_url_set.dart' show MemoryUrlListCheckStore;
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import '../domain_layer/usecases/relay_sets/relay_sets.dart';
import '../domain_layer/usecases/relay_sets_engine.dart';
import '../domain_layer/usecases/requests/requests.dart';
import '../domain_layer/usecases/search/search.dart';
import '../domain_layer/usecases/user_relay_lists/user_relay_lists.dart';
import '../domain_layer/usecases/zaps/zaps.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'ndk_config.dart';

/// this class is used to inject all the dependencies \
/// its like playing lego ;)
class Initialization {
  final NdkConfig _ndkConfig;

  /// data sources

  final NdkHttp _httpRequestDS = NdkHttp(http.Client());

  /// repositories with no dependencies

  late final WebSocketClientNostrTransportFactory
  _webSocketNostrTransportFactory;

  /// state obj

  /// use cases

  late RelayManager relayManager;
  late CacheRead cacheRead;
  late RelayReqs relayReqs;
  late RelayPublishes relayPublishes;
  late Requests requests;
  late Accounts accounts;
  late Bunkers bunkers;
  late Follows follows;
  late Metadatas metadatas;
  late UserRelayLists userRelayLists;
  late Lists lists;
  late RelaySets relaySets;
  late Broadcast broadcast;
  late PendingBroadcastDelivery pendingBroadcastDelivery;
  late Zaps zaps;
  late Lnurl lnurl;
  late BlossomUserServerList blossomUserServerList;
  late Search search;
  late GiftWrap giftWrap;
  late Connectivy connectivity;
  late DecryptedEventPayloads decryptedEventPayloads;
  late FetchedRanges fetchedRanges;
  CacheEvictionScheduler? cacheEvictionScheduler;
  StreamSubscription<List<RelayConnectivity>>? _relayConnectivitySubscription;
  final Map<String, bool> _relayOpenStates = {};

  late Nip05Usecase nip05;
  late Nip77 nip77;

  late final NetworkEngine engine;

  late final Future<void> bootstrapRelaysConnected;

  /// [NdkConfig] is user defined
  Initialization({required NdkConfig ndkConfig}) : _ndkConfig = ndkConfig {
    // first, so what the use cases log while they are built respects it
    Logger.setLogLevel(_ndkConfig.logLevel);

    final userAgent = ndkConfig.userAgent;
    if (userAgent != null) configureDefaultUserAgent(userAgent);

    _webSocketNostrTransportFactory = WebSocketClientNostrTransportFactory(
      compressionEnabled: ndkConfig.webSocketCompression,
      pingInterval: ndkConfig.webSocketPingInterval,
    );

    accounts = Accounts(_ndkConfig.eventSignerFactory);

    relayManager = RelayManager(
      accounts: accounts,
      nostrTransportFactory: _webSocketNostrTransportFactory,
      authCallbackTimeout: _ndkConfig.authCallbackTimeout,
      authHandler: _ndkConfig.authHandler,
      reconnectMaximumStep: _ndkConfig.webSocketReconnectMaximumStep,
    );
    // connectRelay reports its failures in its record, so this never fails
    bootstrapRelaysConnected = Future.wait(
      _ndkConfig.bootstrapRelays.map(
        (url) => relayManager.connectRelay(dirtyUrl: url),
      ),
    );

    switch (_ndkConfig.engine) {
      case NdkEngine.RELAY_SETS:
        engine = RelaySetsEngine(
          bootstrapRelays: _ndkConfig.bootstrapRelays,
          bootstrapRelaysConnected: bootstrapRelaysConnected,
        );
        break;
      case NdkEngine.JIT:
        engine = JitEngine(
          cache: _ndkConfig.cache,
          ignoreRelays: _ndkConfig.ignoreRelays,
          relayManagerLight: relayManager,
          bootstrapRelays: _ndkConfig.bootstrapRelays,
          bootstrapRelaysConnected: bootstrapRelaysConnected,
        );
        break;
    }

    /// repositories
    final Nip05Repository nip05repository = Nip05HttpRepositoryImpl(
      httpDS: _httpRequestDS,
    );

    ///   use cases
    cacheRead = CacheRead(_ndkConfig.cache);
    decryptedEventPayloads = DecryptedEventPayloads(
      cacheManager: _ndkConfig.cache,
    );

    relayReqs = RelayReqs(
      relayManager: relayManager,
      eventVerifier: _ndkConfig.eventVerifier,
    );
    relayPublishes = RelayPublishes(relayManager: relayManager);

    requests = Requests(
      defaultQueryTimeout: _ndkConfig.defaultQueryTimeout,
      cacheRead: cacheRead,
      cacheManager: _ndkConfig.cache,
      networkEngine: engine,
      relayManager: relayManager,
      eventVerifier: _ndkConfig.eventVerifier,
      eventOutFilters: _ndkConfig.eventOutFilters,
      debugMode: _ndkConfig.debugMode,
      relayReqs: relayReqs,
    );

    final listCache = CacheManagerReplaceableEvents(_ndkConfig.cache);
    final listChecks = MemoryUrlListCheckStore();
    final nip65Fetcher = Nip65Fetcher(
      reqs: relayReqs,
      relays: _ndkConfig.bootstrapRelays,
      cache: listCache,
      checks: listChecks,
    );
    final urlLists = fetcherUrlListFn(
      nip65: nip65Fetcher,
      dmRelays: DmRelaysFetcher(
        reqs: relayReqs,
        nip65Fetcher: nip65Fetcher,
        relays: _ndkConfig.bootstrapRelays,
        cache: listCache,
        checks: listChecks,
      ),
      blossomServers: BlossomServersFetcher(
        reqs: relayReqs,
        nip65Fetcher: nip65Fetcher,
        relays: _ndkConfig.bootstrapRelays,
        cache: listCache,
        checks: listChecks,
      ),
    );

    final broadcastSender = BroadcastSender(
      urlLists: urlLists,
      bootstrapRelays: _ndkConfig.bootstrapRelays,
      relayManager: relayManager,
      relayPublishes: relayPublishes,
      cacheManager: _ndkConfig.cache,
      accounts: accounts,
      considerDonePercent: _ndkConfig.defaultBroadcastConsiderDonePercent,
      timeout: _ndkConfig.defaultBroadcastTimeout,
      saveToCache: _ndkConfig.defaultBroadcastSaveToCache,
    );
    pendingBroadcastDelivery = PendingBroadcastDelivery(
      store: _ndkConfig.cache,
      accounts: accounts,
      urlLists: urlLists,
      isEventInFlight: broadcastSender.isEventInFlight,
      send: (event, relayUrl, auth) => broadcastSender
          .broadcast(nostrEvent: event, specificRelays: [relayUrl], auth: auth)
          .broadcastDoneFuture,
    );
    broadcast = Broadcast(
      broadcastSender: broadcastSender,
      accounts: accounts,
      cacheManager: _ndkConfig.cache,
      pendingDelivery: pendingBroadcastDelivery,
    );
    if (_ndkConfig.pendingDeliveryRetriesEnabled) {
      _relayConnectivitySubscription = relayManager.relayConnectivityChanges
          .listen(_handleRelayConnectivityUpdate);
      pendingBroadcastDelivery.startPeriodicRetry(
        connectedRelayUrls: () =>
            relayManager.connectedRelays.map((relay) => relay.url),
        reconnectRelay: (relayUrl) =>
            relayManager.reconnectRelay(relayUrl, force: true),
        retryInterval: _ndkConfig.pendingDeliveryRetryInterval,
      );
    }

    bunkers = Bunkers(
      relayReqs: relayReqs,
      relayPublishes: relayPublishes,
      eventSignerFactory: _ndkConfig.eventSignerFactory,
    );

    follows = Follows(
      requests: requests,
      cacheManager: _ndkConfig.cache,
      broadcast: broadcast,
      accounts: accounts,
    );

    metadatas = Metadatas(
      requests: requests,
      cacheManager: _ndkConfig.cache,
      broadcast: broadcast,
      accounts: accounts,
    );

    userRelayLists = UserRelayLists(
      requests: requests,
      cacheManager: _ndkConfig.cache,
      broadcast: broadcast,
      accounts: accounts,
    );

    lists = Lists(
      requests: requests,
      cacheManager: _ndkConfig.cache,
      broadcast: broadcast,
      accounts: accounts,
      eventSignerFactory: _ndkConfig.eventSignerFactory,
      decryptedEventPayloads: decryptedEventPayloads,
    );

    relaySets = RelaySets(
      cacheManager: _ndkConfig.cache,
      userRelayLists: userRelayLists,
      relayManager: relayManager,
      blockedRelays: relayManager.blockedRelays,
    );

    nip05 = Nip05Usecase(
      cache: _ndkConfig.cache,
      nip05Repository: nip05repository,
    );

    final LnurlTransport lnurlTransport = LnurlTransportHttpImpl(
      _httpRequestDS,
    );

    lnurl = Lnurl(transport: lnurlTransport);

    zaps = Zaps(requests: requests, lnurl: lnurl);

    blossomUserServerList = BlossomUserServerList(
      requests: requests,
      broadcast: broadcast,
      accounts: accounts,
    );

    search = Search(cacheManager: _ndkConfig.cache, requests: requests);

    fetchedRanges = FetchedRanges(cacheManager: _ndkConfig.cache);

    // Connect fetchedRanges to requests for automatic range recording (if enabled)
    if (_ndkConfig.fetchedRangesEnabled) {
      requests.fetchedRanges = fetchedRanges;
    }

    giftWrap = GiftWrap(
      signer: () => accounts.getLoggedAccount()?.signer,
      eventVerifier: _ndkConfig.eventVerifier,
      eventSignerFactory: _ndkConfig.eventSignerFactory,
      cache: DecryptedPayloadsGiftWrapCache(decryptedEventPayloads),
    );

    connectivity = Connectivy(
      relayManager,
      RelayInfoHttpRepoImpl(httpDS: _httpRequestDS),
    );

    nip77 = Nip77(
      relayManager: relayManager,
      loadEventIds: _ndkConfig.cache.loadEventIdsWithCreatedAt,
      loadEvent: _ndkConfig.cache.loadEvent,
    );

    if (_ndkConfig.cacheEvictionEnabled) {
      cacheEvictionScheduler = CacheEvictionScheduler(
        cacheManager: _ndkConfig.cache,
        policy: _ndkConfig.cacheEvictionPolicy,
        startupDelay: _ndkConfig.cacheEvictionStartupDelay,
        interval: _ndkConfig.cacheEvictionInterval,
        runOnStartup: _ndkConfig.runCacheEvictionOnStartup,
      )..start();
    }
  }

  /// Close all active NIP-77 negotiations
  void closeAllNip77Negotiations() {
    nip77.closeAll();
  }

  Future<void> dispose() async {
    await cacheEvictionScheduler?.stop();
    await pendingBroadcastDelivery.stop();
    await _relayConnectivitySubscription?.cancel();
    _httpRequestDS.abortPending();
  }

  void _handleRelayConnectivityUpdate(List<RelayConnectivity> connections) {
    // deliveries are still addressed by relay, so a relay counts as reachable
    // as soon as one of its connections is open
    final openByUrl = <String, bool>{};
    for (final connection in connections) {
      openByUrl[connection.url] =
          (openByUrl[connection.url] ?? false) || connection.isConnected;
    }

    for (final entry in openByUrl.entries) {
      final relayUrl = entry.key;
      final wasOpen = _relayOpenStates[relayUrl] ?? false;
      _relayOpenStates[relayUrl] = entry.value;

      if (entry.value && !wasOpen) {
        unawaited(
          pendingBroadcastDelivery.retryInteractiveSigningForTransportRelay(
            relayUrl,
          ),
        );
        unawaited(pendingBroadcastDelivery.flushForRelay(relayUrl));
      }
    }

    final removedUrls = _relayOpenStates.keys
        .where((relayUrl) => !openByUrl.containsKey(relayUrl))
        .toList();
    for (final relayUrl in removedUrls) {
      _relayOpenStates.remove(relayUrl);
    }
  }
}
