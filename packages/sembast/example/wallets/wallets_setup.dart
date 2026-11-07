import 'package:http/http.dart' as http;
import 'package:ndk/ndk.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nwc/ndk_nwc.dart';
import 'package:ndk_sembast/ndk_sembast.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

/// NDK with every wallet type, wallets stored in the Sembast file [filename].
Future<({Ndk ndk, Cashu cashu, Wallets wallets})> setUpWallets({
  String filename = 'wallets_db.db',
}) async {
  final walletsRepo = await SembastWalletsRepo.create(filename: filename);
  final ndk = Ndk(
    NdkConfig(
      cache: MemCacheManager(),
      eventVerifier: Bip340EventVerifier(),
      bootstrapRelays: const [],
    ),
  );
  final nwc = Nwc(
    query: (filter, {required relays, required timeout, onTimeout}) => ndk
        .requests
        .query(
          filter: filter,
          explicitRelays: relays,
          timeout: timeout,
          timeoutCallback: onTimeout,
          cacheRead: false,
          cacheWrite: false,
        )
        .future,
    subscribe: (filter, {required relays}) {
      final response = ndk.requests.subscription(
        filter: filter,
        explicitRelays: relays,
      );
      return (
        events: response.stream,
        sent: (timeout) =>
            ndk.relays.waitForRequestSent(response.requestId, timeout),
        close: () => ndk.requests.closeSubscription(response.requestId),
      );
    },
    publish: (event, {required relays, required signer}) => ndk.broadcast
        .broadcast(
          nostrEvent: event,
          specificRelays: relays,
          customSigner: signer,
          retryDelivery: false,
          saveToCache: false,
        )
        .broadcastDoneFuture,
    eventSignerFactory: ndk.config.eventSignerFactory,
    zaps: ndk.zaps,
  );
  final cashuHttp = NdkHttp(http.Client());
  final cashu = Cashu(
    cashuRepo: CashuRepoImpl(client: cashuHttp),
    walletsRepo: walletsRepo,
    storage: MemCashuStorage(),
    cashuKeyDerivation: DartCashuKeyDerivation(),
    cashuUserSeedphrase: CashuUserSeedphrase(
      seedPhrase: CashuSeed.generateSeedPhrase(),
    ),
  );
  final wallets = Wallets(
    repository: walletsRepo,
    providers: [
      CashuWalletProvider(cashu),
      NwcWalletProvider(nwc),
      LnurlWalletProvider(ndk.lnurl),
      const Bolt12WalletProvider(),
      LnBitsWalletProvider(),
    ],
  );
  ndk.addLifecycleHooks(
    onDestroy: () async {
      await nwc.disconnectAll();
      cashuHttp.abortPending();
      await wallets.dispose();
    },
  );
  return (ndk: ndk, cashu: cashu, wallets: wallets);
}
