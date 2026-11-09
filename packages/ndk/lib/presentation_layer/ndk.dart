import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_broadcast/ndk_broadcast.dart';
import 'package:ndk_blossom/ndk_blossom.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_nip17/ndk_nip17.dart';
import 'package:ndk_nip82/ndk_nip82.dart';
import 'package:ndk_nip85/ndk_nip85.dart';
import 'package:ndk_nwc/ndk_nwc.dart';
import 'package:ndk_wallets/ndk_wallets.dart';
import 'package:ndk_nip46/ndk_nip46.dart';
import 'connectivity.dart';
import 'package:ndk_requests/ndk_requests.dart';
import 'package:ndk_follows/ndk_follows.dart';
import 'package:ndk_nip59/ndk_nip59.dart';
import 'package:ndk_lists/ndk_lists.dart';
import 'package:ndk_metadatas/ndk_metadatas.dart';
import 'package:ndk_nip05/ndk_nip05.dart';
import 'package:ndk_nip77/ndk_nip77.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_user_relay_lists/ndk_user_relay_lists.dart';
import 'package:ndk_zaps/ndk_zaps.dart';
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
  Connectivity get connectivity => _initialization.connectivity;

  /// Background cache eviction scheduler, when enabled in config.
  CacheEvictionScheduler? get cacheEvictionScheduler =>
      _initialization.cacheEvictionScheduler;

  /// Read-through cache for decrypted event payloads.
  ///
  /// Lets callers cache plaintext sidecars keyed by `(eventId, viewerPubKey)`
  /// so remote signers do not need to decrypt the same event repeatedly.
  DecryptedEventPayloads get decryptedEventPayloads =>
      _initialization.decryptedEventPayloads;

  /// Registers callbacks run by [setBackgrounded] and [destroy], in
  /// registration order. Usecases built outside of this instance use it to
  /// follow its lifecycle.
  void addLifecycleHooks({
    Future<void> Function(bool backgrounded)? onBackgrounded,
    Future<void> Function()? onDestroy,
  }) {
    if (onBackgrounded != null) _backgroundedHooks.add(onBackgrounded);
    if (onDestroy != null) _destroyHooks.add(onDestroy);
  }

  /// Suspends wallet notifications and balance polling, runs the background
  /// hooks registered with [addLifecycleHooks], and closes idle relay
  /// connections when the application enters background. Active requests keep
  /// their connections.
  Future<void> setBackgrounded(bool backgrounded) async {
    await _initialization.setBackgrounded(backgrounded);
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

  /// manage files on nostr \
  /// upload, download, delete files \
  /// high level usecase, recommended for most users
  Files get files => _initialization.files;

  /// Blossom usecase \
  /// upload, download, delete, list files \
  /// low level usecase, recommended for advanced users
  Blossom get blossom => _initialization.blossom;

  /// The kind 10063 list of the Blossom servers a user uploads to (BUD-03)
  BlossomUserServerList<List<RelayBroadcastResponse>>
  get blossomUserServerList => _initialization.blossomUserServerList;

  /// Direct messages usecase.
  ///
  /// App-facing alias for NIP-17 private direct messages.
  Dms get dms => _initialization.dms;

  /// Nostr Wallet connect
  ///
  /// Experimental: the API might change, it needs more docs and tests.
  Nwc get nwc => _initialization.nwc;

  /// Cashu Wallet
  ///
  /// Experimental: in development.
  Cashu get cashu => _initialization.cashu;

  /// Wallet combining all wallet accounts
  ///
  /// Experimental: the API might change.
  Wallets get wallets => _initialization.wallets;

  /// NIP-82 software application, release, and asset discovery.
  Software get software => _initialization.software;

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

  /// Search
  ///
  /// Experimental: the API might change.
  Search get search => _initialization.search;

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

  /// Close all transports on relay manager
  Future<void> destroy() async {
    _initialization.requests.clearVerifiedEventCache();

    final allFutures = [
      _initialization.dispose(),
      Future(() => _initialization.closeAllNip77Negotiations()),
      _initialization.disposeLazyUsecases(),
      ..._destroyHooks.map((hook) => hook()),
      _initialization.requests.closeAllSubscription(),
      _initialization.relayManager.closeAllTransports(),
      accounts.dispose(),
    ];

    await Future.wait(allFutures);
    _initialization.requests.clearVerifiedEventCache();
  }
}
