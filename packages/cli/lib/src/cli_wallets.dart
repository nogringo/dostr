import 'package:http/http.dart' as http;
import 'package:ndk/ndk.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_nwc/ndk_nwc.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

/// Wallet usecases, created on first use so that commands without wallets
/// open no wallet connection and resume no Cashu quote.
class CliWallets {
  CliWallets(this._ndk, this._repository);

  final Ndk _ndk;
  final WalletsRepo _repository;

  late final Nwc nwc = _createNwc();

  late final Cashu cashu = _createCashu();

  late final Wallets wallets = _createWallets();

  Nwc _createNwc() {
    final nwc = Nwc(
      query: (filter, {required relays, required timeout, onTimeout}) => _ndk
          .requests
          .query(
            name: 'nwc',
            filter: filter,
            explicitRelays: relays,
            timeout: timeout,
            timeoutCallback: onTimeout,
            cacheRead: false,
            cacheWrite: false,
          )
          .future,
      subscribe: (filter, {required relays}) {
        final response = _ndk.requests.subscription(
          name: 'nwc',
          filter: filter,
          explicitRelays: relays,
        );
        return (
          events: response.stream,
          sent: (timeout) =>
              _ndk.relays.waitForRequestSent(response.requestId, timeout),
          close: () => _ndk.requests.closeSubscription(response.requestId),
        );
      },
      publish: (event, {required relays, required signer}) => _ndk.broadcast
          .broadcast(
            nostrEvent: event,
            specificRelays: relays,
            customSigner: signer,
            retryDelivery: false,
            saveToCache: false,
          )
          .broadcastDoneFuture,
      eventSignerFactory: _ndk.config.eventSignerFactory,
      zaps: _ndk.zaps,
    );
    _ndk.addLifecycleHooks(onDestroy: nwc.disconnectAll);
    return nwc;
  }

  Cashu _createCashu() {
    final client = NdkHttp(http.Client());
    _ndk.addLifecycleHooks(onDestroy: () async => client.abortPending());
    return Cashu(
      cashuRepo: CashuRepoImpl(client: client),
      walletsRepo: _repository,
      storage: switch (_ndk.config.cache) {
        CashuStorage storage => storage,
        _ => MemCashuStorage(),
      },
      cashuKeyDerivation: DartCashuKeyDerivation(),
      mintRecommendations: CashuMintRecommendations(
        query: (filter, {required relays, required timeout}) => _ndk.requests
            .query(filter: filter, explicitRelays: relays, timeout: timeout)
            .future,
      ),
    );
  }

  Wallets _createWallets() {
    final wallets = Wallets(
      repository: _repository,
      providers: [
        CashuWalletProvider(cashu),
        NwcWalletProvider(nwc),
        LnurlWalletProvider(_ndk.lnurl),
        const Bolt12WalletProvider(),
        LnBitsWalletProvider(),
      ],
    );
    _ndk.addLifecycleHooks(onDestroy: wallets.dispose);
    return wallets;
  }
}
