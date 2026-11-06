import '../data_layer/repositories/cache_manager/mem_cache_manager.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import '../domain_layer/usecases/accounts/accounts.dart';
import '../domain_layer/usecases/broadcast/broadcast.dart';
import '../domain_layer/usecases/blossom_user_server_list/blossom_user_server_list.dart';
import '../domain_layer/usecases/bunkers/bunkers.dart';
import '../domain_layer/usecases/cache_eviction/cache_eviction_scheduler.dart';
import '../domain_layer/usecases/connectivity/connectivity.dart';
import '../domain_layer/usecases/decrypted_event_payloads/decrypted_event_payloads.dart';
import '../domain_layer/usecases/fetched_ranges/fetched_ranges.dart';
import '../domain_layer/usecases/follows/follows.dart';
import '../domain_layer/usecases/gift_wrap/gift_wrap.dart';
import '../domain_layer/usecases/lnurl/lnurl.dart';
import '../domain_layer/usecases/lists/lists.dart';
import '../domain_layer/usecases/metadatas/metadatas.dart';
import '../domain_layer/usecases/nip05/nip_05.dart';
import 'package:ndk_nip77/ndk_nip77.dart';
import '../domain_layer/usecases/proof_of_work/proof_of_work.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';
import '../domain_layer/usecases/relay_sets/relay_sets.dart';
import '../domain_layer/usecases/requests/requests.dart';
import '../domain_layer/usecases/search/search.dart';
import '../domain_layer/usecases/software/software.dart';
import '../domain_layer/usecases/ta/trusted_assertions.dart';
import '../domain_layer/usecases/user_relay_lists/user_relay_lists.dart';
import '../domain_layer/usecases/zaps/zaps.dart';
import 'init.dart';
import 'ndk_config.dart';

/// Main entry point for the NDK (Nostr Development Kit) library.
///
/// This file contains the primary class [Ndk] which provides access to various
/// Nostr-related functionalities/usecases and manages the state of this NDK instance.
class Ndk {
  /// Configuration for the NDK instance
  final NdkConfig config;

  /// Internal initialization object for setting up repositories and usecases
  late final Initialization _initialization;

  final List<Future<void> Function(bool backgrounded)> _backgroundedHooks = [];
  final List<Future<void> Function()> _destroyHooks = [];

  /// Creates a new instance of [Ndk] with the given [config]
  Ndk(this.config) {
    _initialization = Initialization(ndkConfig: config);
  }

  /// Creates a new instance of [Ndk] with default configuration
  Ndk.defaultConfig()
    : this(
        NdkConfig(
          cache: MemCacheManager(),
          eventVerifier: Bip340EventVerifier(),
        ),
      );

  /// Creates a new instance of [Ndk] with default configuration and empty bootstrap relays
  Ndk.emptyBootstrapRelaysConfig()
    : this(
        NdkConfig(
          cache: MemCacheManager(),
          eventVerifier: Bip340EventVerifier(),
          bootstrapRelays: [],
        ),
      );

  /// Provides access to low-level Nostr requests.
  ///
  /// Use this to directly query or subscribe to notes from the Nostr network. \
  /// Available methods include query() and subscription()
  Requests get requests => _initialization.requests;

  /// NIP-01 REQs on relays you pick, below [requests]: no cache, no outbox
  /// routing, no dedup across relays.
  RelayReqs get relayReqs => _initialization.relayReqs;

  /// Signed events published to relays you pick, below [broadcast]: no
  /// signing, no cache, no outbox routing, no retry.
  RelayPublishes get relayPublishes => _initialization.relayPublishes;

  /// Accounts
  Accounts get accounts => _initialization.accounts;

  /// Bunker - NIP-46 remote signing protocol
  Bunkers get bunkers => _initialization.bunkers;

  /// Provides access to low-level Nostr broadcast/publish.
  ///
  /// high level broadcast operations like updating lists, etc are already included in the specific usecases
  Broadcast get broadcast => _initialization.broadcast;

  /// Relay Manager
  RelayManager get relays => _initialization.relayManager;

  /// Completes once every relay of [NdkConfig.bootstrapRelays] has connected
  /// or failed to.
  Future<void> get bootstrapRelaysConnected =>
      _initialization.bootstrapRelaysConnected;

  /// Handles operations related to user follows
  ///
  /// Use getContactList() to retrieve contact lists
  Follows get follows => _initialization.follows;

  /// user metadata operations
  Metadatas get metadata => _initialization.metadatas;

  /// user relay lists usecase \
  /// similar to nip65 but more generic, contact list relays can also be considered
  UserRelayLists get userRelayLists => _initialization.userRelayLists;

  /// Manages various types of lists in the Nostr network
  Lists get lists => _initialization.lists;

  /// calculate relay set
  RelaySets get relaySets => _initialization.relaySets;

  /// NIP-05 operations (verify and fetch)
  Nip05Usecase get nip05 => _initialization.nip05;

  /// Gift wrap - NIP-59 \
  /// crate gift wraps \
  /// unwrap gift wraps \
  ///
  /// low level usecase, recommended for advanced users
  GiftWrap get giftWrap => _initialization.giftWrap;

  /// Use case for managing relay connectivity \
  /// get notified about relay connectivity changes \
  /// and update NDK about your application connectivity \
  /// for faster reconnects
  Connectivy get connectivity => _initialization.connectivity;

  /// Background cache eviction scheduler, when enabled in config.
  CacheEvictionScheduler? get cacheEvictionScheduler =>
      _initialization.cacheEvictionScheduler;

  /// Read-through cache for decrypted event payloads.
  ///
  /// Lets callers cache plaintext sidecars keyed by `(eventId, viewerPubKey)`
  /// so remote signers do not need to decrypt the same event repeatedly.
  DecryptedEventPayloads get decryptedEventPayloads =>
      _initialization.decryptedEventPayloads;

  ProofOfWork get proofOfWork => _initialization.proofOfWork;

  /// Registers callbacks run by [setBackgrounded] and [destroy], in
  /// registration order. Add-on packages such as ndk_nwc and ndk_wallets use
  /// it to follow the lifecycle of this instance.
  void addLifecycleHooks({
    Future<void> Function(bool backgrounded)? onBackgrounded,
    Future<void> Function()? onDestroy,
  }) {
    if (onBackgrounded != null) _backgroundedHooks.add(onBackgrounded);
    if (onDestroy != null) _destroyHooks.add(onDestroy);
  }

  /// Runs the background hooks registered with [addLifecycleHooks] (wallet
  /// notifications and balance polling are suspended), and closes idle relay
  /// connections when the application enters background. Active requests keep
  /// their connections.
  Future<void> setBackgrounded(bool backgrounded) async {
    for (final hook in List.of(_backgroundedHooks)) {
      await hook(backgrounded);
    }
    if (backgrounded) await relays.closeIdleConnections();
  }

  /// Zaps
  ///
  /// Experimental: the API might change, it needs more docs and tests.
  Zaps get zaps => _initialization.zaps;

  /// LNURL-pay (LUD-06/LUD-16) lookups and invoice fetching
  Lnurl get lnurl => _initialization.lnurl;

  /// The kind 10063 list of the Blossom servers a user uploads to (BUD-03)
  BlossomUserServerList get blossomUserServerList =>
      _initialization.blossomUserServerList;

  /// Search
  ///
  /// Experimental: the API might change.
  Search get search => _initialization.search;

  /// NIP-82 software application, release, and asset discovery.
  Software get software => _initialization.software;

  /// Fetched ranges tracking
  /// Track which time ranges have been fetched from which relays for each filter
  ///
  /// Experimental: the API might change.
  FetchedRanges get fetchedRanges => _initialization.fetchedRanges;

  /// NIP-77 Negentropy sync
  /// Efficient set reconciliation for syncing events between client and relay
  ///
  /// Experimental: the API might change.
  Nip77 get nip77 => _initialization.nip77;

  /// Trusted Assertions (NIP-85)
  ///
  /// Fetch pre-computed metrics from trusted service providers.
  ///
  /// Experimental: the API might change.
  TrustedAssertions get ta => _initialization.trustedAssertions;

  /// Trusted Assertions (NIP-85)
  ///
  /// Fetch pre-computed metrics from trusted service providers.
  /// short alias for trusted assertions => ndk.ta.getMetrics()
  ///
  /// Experimental: the API might change.
  TrustedAssertions get trustedAssertions => ta;

  /// Close all transports on relay manager
  Future<void> destroy() async {
    _initialization.requests.clearVerifiedEventCache();

    final allFutures = [
      _initialization.dispose(),
      Future(() => _initialization.closeAllNip77Negotiations()),
      ..._destroyHooks.map((hook) => hook()),
      _initialization.requests.closeAllSubscription(),
      _initialization.relayManager.closeAllTransports(),
      _initialization.requests.closeAllSubscription(),
      accounts.dispose(),
    ];

    await Future.wait(allFutures);
    _initialization.requests.clearVerifiedEventCache();
  }
}
