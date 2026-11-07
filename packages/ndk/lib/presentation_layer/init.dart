import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nip11/ndk_nip11.dart';
import 'connectivity.dart';
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_broadcast/ndk_broadcast.dart';
import 'package:ndk_blossom/ndk_blossom.dart' show BlossomUserServerList;
import 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
import 'package:ndk_nip46/ndk_nip46.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_requests/ndk_requests.dart';
import 'package:ndk_follows/ndk_follows.dart';
import 'package:ndk_nip59/ndk_nip59.dart';
import 'package:ndk_lists/ndk_lists.dart';
import 'package:ndk_metadatas/ndk_metadatas.dart';
import 'package:ndk_nip05/ndk_nip05.dart';
import 'package:ndk_fetchers/ndk_fetchers.dart'
    show BlossomServersFetcher, DmRelaysFetcher, Nip65Fetcher, fetcherUrlListFn;
import 'package:ndk_nip77/ndk_nip77.dart';
import 'package:ndk_url_set/ndk_url_set.dart' show MemoryUrlListCheckStore;
import 'package:ndk_search/ndk_search.dart';
import 'package:ndk_user_relay_lists/ndk_user_relay_lists.dart';
import 'package:ndk_zaps/ndk_zaps.dart';
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
  late BlossomUserServerList<List<RelayBroadcastResponse>>
  blossomUserServerList;
  late Search search;
  late GiftWrap giftWrap;
  late Connectivy connectivity;
  late DecryptedEventPayloads decryptedEventPayloads;
  late FetchedRanges fetchedRanges;
  CacheEvictionScheduler? cacheEvictionScheduler;

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
      pendingBroadcastDelivery.startPeriodicRetry(
        connectedRelayUrls: () =>
            relayManager.connectedRelays.map((relay) => relay.url),
        reconnectRelay: (relayUrl) =>
            relayManager.reconnectRelay(relayUrl, force: true),
        retryInterval: _ndkConfig.pendingDeliveryRetryInterval,
        // a relay is reachable as soon as one of its connections is open
        openRelayUrlChanges: relayManager.relayConnectivityChanges.map(
          (connections) => {
            for (final connection in connections)
              if (connection.isConnected) connection.url,
          },
        ),
      );
    }

    bunkers = Bunkers(
      relayReqs: relayReqs,
      relayPublishes: relayPublishes,
      eventSignerFactory: _ndkConfig.eventSignerFactory,
    );

    follows = Follows(
      query: (filter, {required timeout}) =>
          requests.query(filter: filter, timeout: timeout).future,
      publish: (event, {relays}) => broadcast
          .broadcast(nostrEvent: event, specificRelays: relays)
          .broadcastDoneFuture,
      cache: _ndkConfig.cache,
      accounts: accounts,
    );

    metadatas = Metadatas(
      query: (filter, {timeout, required cacheRead, relays}) => requests
          .query(
            name: 'metadatas',
            filter: filter,
            timeout: timeout,
            cacheRead: cacheRead,
            explicitRelays: relays,
          )
          .stream,
      publish: (event, {relays}) => broadcast
          .broadcast(nostrEvent: event, specificRelays: relays)
          .broadcastDoneFuture,
      cache: _ndkConfig.cache,
      accounts: accounts,
    );

    userRelayLists = UserRelayLists(
      query: (filter, {required name, relays}) => requests
          .query(name: name, filter: filter, explicitRelays: relays)
          .stream,
      publish: (event, {required relays}) => broadcast
          .broadcast(nostrEvent: event, specificRelays: relays)
          .broadcastDoneFuture,
      cacheManager: _ndkConfig.cache,
      accounts: accounts,
    );

    lists = Lists(
      query: (filter, {timeout, required cacheRead}) => requests
          .query(
            name: 'lists',
            filter: filter,
            timeout: timeout,
            cacheRead: cacheRead,
          )
          .stream,
      publish: (event, {relays}) => broadcast
          .broadcast(nostrEvent: event, specificRelays: relays)
          .broadcastDoneFuture,
      cache: _ndkConfig.cache,
      accounts: accounts,
      plaintextCache: DecryptedPayloadsNip51ListCache(decryptedEventPayloads),
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

    lnurl = Lnurl(transport: LnurlTransportHttpImpl(_httpRequestDS));

    zaps = Zaps(
      query: (filter, {required timeout}) =>
          requests.query(name: 'zaps', filter: filter, timeout: timeout).stream,
      subscribe: (filter) {
        final response = requests.subscription(name: 'zaps', filter: filter);
        return (
          events: response.stream,
          close: () => requests.closeSubscription(response.requestId),
        );
      },
      lnurl: lnurl,
    );

    blossomUserServerList = BlossomUserServerList(
      query: ({required authors, required kind, required timeout}) => requests
          .query(
            filter: Filter(authors: authors, kinds: [kind]),
            timeout: timeout,
          )
          .future,
      publish: (event) =>
          broadcast.broadcast(nostrEvent: event).broadcastDoneFuture,
      accounts: accounts,
    );

    search = Search(
      query: (filter) => requests.query(name: 'search', filter: filter).stream,
      cache: _ndkConfig.cache,
    );

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
    _httpRequestDS.abortPending();
  }
}
