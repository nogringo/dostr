# Wallets (NWC + Cashu)

> Both are `@experimental`. API may change.

Wallet code lives outside `ndk`, in three packages that do not depend on it. Each is built from the parts of an `Ndk` instance it uses:

| Package | Usecase | Takes |
| ------- | ------- | ----- |
| `ndk_nwc` | `Nwc` | `query`, `subscribe` and `publish` callbacks, `eventSignerFactory`, `zaps` |
| `ndk_cashu` | `Cashu` | `cashuRepo`, `walletsRepo`, `storage`, `cashuKeyDerivation`, `mintRecommendations` |
| `ndk_wallets` | `Wallets` | `repository`, `providers` |

None of them registers on the NDK lifecycle. Register their cleanup with `ndk.addLifecycleHooks(...)`, so that `ndk.destroy()` closes them and `ndk.setBackgrounded(...)` pauses their background work.

## Nostr Wallet Connect (NWC)

```dart
import 'package:ndk_nwc/ndk_nwc.dart';

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
ndk.addLifecycleHooks(
  onBackgrounded: nwc.setBackgrounded,
  onDestroy: nwc.disconnectAll,
);

// Connect wallet
final connection = await nwc.connect('nostr+walletconnect://...');

// Balance
final balance = await nwc.getBalance(connection);
print(balance.balanceSats);

// Pay invoice
final result = await nwc.payInvoice(connection, invoice: 'lnbc...');

// Get invoice
final invoice = await nwc.makeInvoice(
  connection,
  amountSats: 1000,
  description: 'test',
);

// List transactions
final txs = await nwc.listTransactions(connection);

// Zap an lnurl through this connection
final zap = await nwc.zap(
  nwcConnection: connection,
  lnurl: 'name@domain.com',
  amountSats: 21,
);

// Disconnect all
await nwc.disconnectAll();
```

## Cashu (e-cash)

```dart
import 'package:http/http.dart' as http;
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_http/ndk_http.dart';

// Generate new seed phrase (store securely!)
final seed = CashuSeed.generateSeedPhrase();

final cashuHttp = NdkHttp(http.Client());
final cashu = Cashu(
  cashuRepo: CashuRepoImpl(client: cashuHttp),
  walletsRepo: walletsRepo,
  storage: MemCashuStorage(),
  cashuKeyDerivation: DartCashuKeyDerivation(),
  mintRecommendations: CashuMintRecommendations(
    query: (filter, {required relays, required timeout}) => ndk.requests
        .query(filter: filter, explicitRelays: relays, timeout: timeout)
        .future,
  ),
  cashuUserSeedphrase: CashuUserSeedphrase(seedPhrase: seed),
);
ndk.addLifecycleHooks(onDestroy: () async => cashuHttp.abortPending());
```

Proofs and keysets go to `storage`, a `CashuStorage`: the NDK cache when it implements it (`ndk_objectbox`, `ndk_drift`, `ndk_sembast`, `ndk_sqlite3`), else `MemCashuStorage`. `mintRecommendations` answers `discoverMintRecommendations`.

## Combined Wallets usecase

`Wallets` aggregates every wallet type behind one API, one provider per type.

```dart
import 'package:ndk_wallets/ndk_wallets.dart';

// nwc and cashu built as above, cashu with this walletsRepo
final walletsRepo = await SembastWalletsRepo.create(filename: 'wallets.db');
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
  onBackgrounded: (backgrounded) async => wallets.setBackgrounded(backgrounded),
  onDestroy: wallets.dispose,
);

wallets.walletsStream; // Stream<List<Wallet>>
wallets.combinedBalances; // Stream<List<WalletBalance>>
```
