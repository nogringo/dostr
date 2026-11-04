# Wallets (NWC + Cashu)

> Both are `@experimental`. API may change.

Wallet code lives outside the `ndk` core, in three packages built on an `Ndk` instance:

| Package | Usecase | Construct |
| ------- | ------- | --------- |
| `ndk_nwc` | `Nwc` | `Nwc(ndk)` |
| `ndk_cashu` | `Cashu` | `Cashu(ndk, cashuUserSeedphrase: ...)` |
| `ndk_wallets` | `Wallets` | `Wallets(ndk, providers: [...])` |

`Nwc` and `Wallets` register on the NDK lifecycle: `ndk.destroy()` closes them and `ndk.setBackgrounded(...)` pauses their background work.

## Nostr Wallet Connect (NWC)

```dart
import 'package:ndk_nwc/ndk_nwc.dart';

final nwc = Nwc(ndk);

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
import 'package:ndk_cashu/ndk_cashu.dart';

// Generate new seed phrase (store securely!)
final seed = CashuSeed.generateSeedPhrase();

final cashu = Cashu(
  ndk,
  cashuUserSeedphrase: CashuUserSeedphrase(seedPhrase: seed),
);
```

Proofs and keysets go to a `CashuStorage`: the NDK cache when it implements it (`ndk_objectbox`, `ndk_drift`, `ndk_sembast`, `ndk_sqlite3`), else `MemCashuStorage`. Pass `storage:` to choose.

## Combined Wallets usecase

`Wallets` aggregates every wallet type behind one API, one provider per type.

```dart
import 'package:ndk_wallets/ndk_wallets.dart';

final walletsRepo = await SembastWalletsRepo.create(filename: 'wallets.db');
final nwc = Nwc(ndk);
final cashu = Cashu(
  ndk,
  walletsRepo: walletsRepo,
  cashuUserSeedphrase: CashuUserSeedphrase(seedPhrase: seed),
);
final wallets = Wallets(
  ndk,
  repository: walletsRepo,
  providers: [
    CashuWalletProvider(cashu),
    NwcWalletProvider(nwc),
    LnurlWalletProvider(ndk.lnurl),
    const Bolt12WalletProvider(),
    LnBitsWalletProvider(),
  ],
);

wallets.walletsStream; // Stream<List<Wallet>>
wallets.combinedBalances; // Stream<List<WalletBalance>>
```
