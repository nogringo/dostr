import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_requests/ndk_requests.dart';

enum Engine { relaySets, jit }

/// The part of `Ndk` that queries, subscribes and publishes to chosen relays,
/// wired the way its `Initialization` does with a default `NdkConfig`.
class RequestsClient {
  RequestsClient({
    required EventVerifier eventVerifier,
    CacheManager? cache,
    Engine engine = Engine.relaySets,
    this.bootstrapRelays = const [],
    List<String> ignoreRelays = const [],
    AuthHandler? authHandler,
    Duration defaultQueryTimeout = const Duration(seconds: 10),
    List<EventFilter> eventOutFilters = const [],
    bool debugMode = false,
    LogLevel logLevel = defaultLogLevel,
  }) : cache = cache ?? MemCacheManager() {
    Logger.setLogLevel(logLevel);
    relays = RelayManager(
      accounts: accounts,
      nostrTransportFactory: WebSocketClientNostrTransportFactory(),
      authHandler: authHandler,
    );
    bootstrapRelaysConnected = Future.wait(
      bootstrapRelays.map((url) => relays.connectRelay(dirtyUrl: url)),
    );
    relayReqs = RelayReqs(relayManager: relays, eventVerifier: eventVerifier);
    relayPublishes = RelayPublishes(relayManager: relays);
    requests = Requests(
      defaultQueryTimeout: defaultQueryTimeout,
      cacheRead: CacheRead(this.cache),
      cacheManager: this.cache,
      networkEngine: switch (engine) {
        Engine.relaySets => RelaySetsEngine(
          bootstrapRelays: bootstrapRelays,
          bootstrapRelaysConnected: bootstrapRelaysConnected,
        ),
        Engine.jit => JitEngine(
          cache: this.cache,
          ignoreRelays: ignoreRelays,
          relayManagerLight: relays,
          bootstrapRelays: bootstrapRelays,
          bootstrapRelaysConnected: bootstrapRelaysConnected,
        ),
      },
      relayManager: relays,
      eventVerifier: eventVerifier,
      eventOutFilters: eventOutFilters,
      debugMode: debugMode,
      relayReqs: relayReqs,
    );
  }

  final CacheManager cache;
  final List<String> bootstrapRelays;
  final Accounts accounts = Accounts(const Bip340EventSignerFactory());
  late final RelayManager relays;
  late final RelayReqs relayReqs;
  late final RelayPublishes relayPublishes;
  late final Requests requests;
  late final Future<void> bootstrapRelaysConnected;

  Future<void> destroy() async {
    requests.clearVerifiedEventCache();
    await Future.wait([
      requests.closeAllSubscription(),
      relays.closeAllTransports(),
      accounts.dispose(),
    ]);
    requests.clearVerifiedEventCache();
  }
}
