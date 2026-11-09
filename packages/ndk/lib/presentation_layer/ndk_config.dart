import 'package:ndk/config/bootstrap_relays.dart';
import 'package:ndk/config/broadcast_defaults.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk/config/request_defaults.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_core/ndk_core.dart'
    show MessageLengthLimit, SubscriptionLimit;
import 'package:ndk_nip85/ndk_nip85.dart';
import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

/// Configuration class for the Nostr Development Kit (NDK)
///
/// This class holds various settings and dependencies required for
/// the NDK to function properly
class NdkConfig {
  /// The verifier used to validate Nostr events. E.g. Bip340EventVerifier, or RustEventVerifier from ndk_rust_verifier
  EventVerifier eventVerifier;

  /// The cache manager (DB) used to store and retrieve Nostr data. E.g MemCacheManager()
  CacheManager cache;

  /// Where [Ndk.wallets] and [Ndk.cashu] store the wallets. E.g MemWalletsRepo() \
  /// Defaults to [cache] when it stores wallets, to nothing otherwise.
  WalletsRepo? walletsRepo;

  /// Factory for creating EventSigner instances. Defaults to Bip340EventSigner.
  LocalEventSignerFactory eventSignerFactory;

  /// The engine mode to use for Nostr network operations (inbox/outbox mode).
  ///
  /// Defaults to [NdkEngine.RELAY_SETS].
  NdkEngine engine;

  /// A list of relay URLs to ignore for inbox/outbox operations.
  List<String> ignoreRelays;

  /// A list of initial relay URLs to use for bootstrapping the network.
  /// These connect on start.
  ///
  /// Defaults to [DEFAULT_BOOTSTRAP_RELAYS].
  List<String> bootstrapRelays;

  /// filters that are applied to the output stream
  List<EventFilter> eventOutFilters;

  /// default timeout for queries \
  /// this value is used if no individual timeout is set for a query
  Duration defaultQueryTimeout;

  /// timeout for broadcasts
  Duration defaultBroadcastTimeout;

  /// percentage of relays that need to respond with "OK" for the broadcast to be considered done \
  /// value between 0.0 and 1.0
  double defaultBroadcastConsiderDonePercent;

  /// whether to save broadcasted events to cache by default
  bool defaultBroadcastSaveToCache;

  /// log level
  LogLevel logLevel;

  /// cashu user seed phrase, required for using cashu features \
  /// you can use CashuSeed.generateSeedPhrase() to generate a new seed phrase \
  /// Store this securely! Seed phrase allow full access to cashu funds!
  final CashuUserSeedphrase? cashuUserSeedphrase;

  /// when false (default), automatic cashu quote completion on startup
  /// requires an explicit `Cashu.restore()` call for the mint/unit first;
  /// when true, it instead runs a bounded NUT-09 scan itself to verify the
  /// mint derivation counter before minting. See [Cashu.retrieveFunds].
  bool autoVerifyMintCounters;

  /// User agent for websockets on dart:io, set globally on `WebSocket.userAgent`.
  ///
  /// Null (default) leaves the app's user agent untouched. Pass
  /// [RequestDefaults.DEFAULT_USER_AGENT] to identify as NDK.
  String? userAgent;

  /// Whether native WebSocket connections negotiate per-message compression.
  ///
  /// Defaults to true, preserving existing behavior. Disable this to reduce
  /// memory and codec overhead at the cost of sending more bytes for
  /// compressible traffic. Browser WebSocket APIs do not expose compression
  /// controls, so this option has no effect on web builds.
  bool webSocketCompression;

  /// Native WebSocket heartbeat interval. Null disables client pings.
  ///
  /// Longer intervals reduce idle network traffic, but also delay detection of
  /// silent connection failures (the pong timeout equals this interval).
  /// Browser WebSocket APIs do not expose heartbeat controls.
  Duration? webSocketPingInterval;

  /// Maximum exponential reconnect step, starting at 500 milliseconds.
  ///
  /// The default of 4 caps retries at 4 seconds. For example, 7 caps retries
  /// at 32 seconds. This only affects failed connections, not event delivery
  /// on healthy connections.
  int webSocketReconnectMaximumStep;

  /// Enable fetched ranges tracking.
  /// When enabled, NDK tracks which time ranges have been fetched from which relays.
  /// Disabled by default for performance.
  bool fetchedRangesEnabled;

  /// Has no effect. A connection now carries at most one identity, chosen when
  /// it is opened: an anonymous connection never answers a challenge and a
  /// bound one always does, so there is nothing left to choose.
  @Deprecated('Has no effect, a connection is bound to an identity or to none')
  bool eagerAuth;

  /// Timeout for AUTH callbacks (how long to wait for AUTH OK response).
  /// Defaults to 30 seconds.
  Duration authCallbackTimeout;

  /// Asked before an identity authenticates on a relay or a Blossom server.
  /// Without it, a request that does not pass `auth` reveals no identity.
  /// `(_, _) async => true` authenticates as the logged account wherever asked.
  AuthHandler? authHandler;

  /// How many REQs a relay keeps open on one websocket, asked each time a
  /// socket opens. Null, or a null answer for a relay, falls back on its NIP-11
  /// `limitation.max_subscriptions`, then on 20.
  SubscriptionLimit? subscriptionLimit;

  /// How many UTF-8 bytes a relay reads in one message, asked each time a
  /// socket opens. Null, or a null answer for a relay, falls back on its NIP-11
  /// `limitation.max_message_length`. A longer message is not sent to it. A
  /// relay that closes a socket with a 1009 shows it reads less: [cache] keeps
  /// that limit, which applies whatever this answers.
  MessageLengthLimit? messageLengthLimit;

  /// Interval for retrying pending broadcast deliveries while relays remain connected.
  Duration pendingDeliveryRetryInterval;

  /// Whether persisted broadcast deliveries are retried automatically in the
  /// background.
  ///
  /// Disable this for short-lived clients such as command-line tools that
  /// should only perform the network work requested by the current command.
  bool pendingDeliveryRetriesEnabled;

  /// Whether background cache eviction scheduling is enabled.
  bool cacheEvictionEnabled;

  /// Cache eviction policy used by the background scheduler.
  EvictionPolicy cacheEvictionPolicy;

  /// Delay before the first scheduled cache eviction run after startup.
  Duration cacheEvictionStartupDelay;

  /// Interval between background cache eviction runs.
  Duration cacheEvictionInterval;

  /// Whether to run cache eviction once on startup before periodic runs.
  bool runCacheEvictionOnStartup;

  /// Default trusted providers for NIP-85 trusted assertions.
  List<Nip85TrustedProvider> defaultTrustedProviders;

  /// Development aid, off by default. Flutter apps can pass `kDebugMode`.
  ///
  /// When enabled:
  /// - request ids sent to relays start with the request name, so relays
  ///   see which usecase opened each subscription. Keep it off in production.
  bool debugMode;

  /// Creates a new instance of [NdkConfig].
  ///
  /// [eventVerifier] The verifier used to validate Nostr events. \
  /// [cache] The cache manager for storing and retrieving Nostr data. \
  /// [eventSignerFactory] Factory for creating EventSigner instances (defaults to Bip340EventSigner). \
  /// [engine] The engine mode to use (defaults to RELAY_SETS). \
  /// [ignoreRelays] A list of relay URLs to ignore (defaults to an empty list). \
  /// [bootstrapRelays] A list of initial relay URLs (defaults to DEFAULT_BOOTSTRAP_RELAYS). \
  /// [eventOutFilters] A list of filters to apply to the output stream (defaults to an empty list). \
  /// [defaultQueryTimeout] The default timeout for queries (defaults to DEFAULT_QUERY_TIMEOUT). \
  /// [logLevel] The log level for the NDK (defaults to warning).
  /// [webSocketCompression] Whether native WebSockets negotiate compression.
  /// [cashuUserSeedphrase] The cashu user seed phrase, required for using cashu features
  NdkConfig({
    required this.eventVerifier,
    required this.cache,
    this.walletsRepo,
    this.eventSignerFactory = const Bip340EventSignerFactory(),
    this.engine = NdkEngine.RELAY_SETS,
    this.ignoreRelays = const [],
    this.bootstrapRelays = DEFAULT_BOOTSTRAP_RELAYS,
    this.eventOutFilters = const [],
    this.defaultQueryTimeout = RequestDefaults.DEFAULT_QUERY_TIMEOUT,
    this.defaultBroadcastTimeout = BroadcastDefaults.TIMEOUT,
    this.defaultBroadcastConsiderDonePercent =
        BroadcastDefaults.CONSIDER_DONE_PERCENT,
    this.defaultBroadcastSaveToCache = BroadcastDefaults.SAVE_TO_CACHE,
    this.logLevel = defaultLogLevel,
    this.cashuUserSeedphrase,
    this.autoVerifyMintCounters = false,
    this.userAgent,
    this.webSocketCompression = true,
    this.webSocketPingInterval = const Duration(seconds: 10),
    this.webSocketReconnectMaximumStep = 4,
    this.fetchedRangesEnabled = false,
    this.eagerAuth = false,
    this.authCallbackTimeout = RequestDefaults.DEFAULT_AUTH_CALLBACK_TIMEOUT,
    this.authHandler,
    this.subscriptionLimit,
    this.messageLengthLimit,
    this.pendingDeliveryRetryInterval = const Duration(seconds: 15),
    this.pendingDeliveryRetriesEnabled = true,
    this.cacheEvictionEnabled = false,
    this.cacheEvictionPolicy = const EvictionPolicy(),
    this.cacheEvictionStartupDelay = const Duration(minutes: 1),
    this.cacheEvictionInterval = const Duration(hours: 1),
    this.runCacheEvictionOnStartup = true,
    this.defaultTrustedProviders = DEFAULT_NIP85_PROVIDERS,
    this.debugMode = false,
  });
}

/// Enum representing different engine modes for Nostr network operations.
enum NdkEngine {
  /// Uses relay sets for network operations.
  // ignore: constant_identifier_names
  RELAY_SETS,

  /// Uses Just-In-Time (JIT) mode for network operations.
  // ignore: constant_identifier_names
  JIT,
}
