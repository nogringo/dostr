---
icon: credit-card
---

[!badge variant="primary" text="high level"]

!!!danger experimental
DO NOT USE IN PRODUCTION!
!!!

## When to use

`Wallets` manages multiple wallet types in one place and gives you a unified API for balances, transaction history, sending, and receiving.

Use it if your app:

- supports more than one wallet type
- needs a single transaction history across wallets
- wants separate defaults for sending and receiving
- wants one high-level API instead of calling `cashu`, `nwc`, or `lnurl` directly

## What is supported

| Wallet type | Add manually | Auto-discovery | Send | Receive | Balance/history |
| --- | --- | --- | --- | --- | --- |
| Cashu | yes | yes, from known mints | yes | yes | yes |
| NWC | yes | no | yes | yes, if the wallet allows `make_invoice` | yes |
| LNURL | yes | no | no | yes | no |

## Basic usage

### install

`Wallets` lives in the `ndk_wallets` package, with the LNURL, BOLT12 and LNbits providers. Cashu and NWC providers come with `ndk_cashu` and `ndk_nwc`.

```yaml
dependencies:
  ndk_wallets: ^0.1.0
  ndk_cashu: ^0.1.0 # Cashu wallets
  ndk_nwc: ^0.1.0 # NWC wallets
```

### initialize

Create `Wallets` on top of your `Ndk` instance, with one provider per wallet type you support.

Wallets are stored in a `WalletsRepo`. Without `repository`, the NDK cache is used when it implements `WalletsRepo` (`ndk_objectbox`, `ndk_drift` and `ndk_sqlite3` do). Pass the same repository to `Cashu`.

- without Flutter, use `SembastWalletsRepo` from the `ndk_sembast` package
- if possible, prefer the optional `ndk_flutter` package and `FlutterSecureStorageWalletsRepo` for more secure wallet storage

```dart
final walletsRepo = await SembastWalletsRepo.create(filename: 'wallets.db');

final ndk = Ndk(
  NdkConfig(cache: cacheManager, eventVerifier: Bip340EventVerifier()),
);

final nwc = Nwc(ndk);
final cashu = Cashu(
  ndk,
  walletsRepo: walletsRepo,
  cashuUserSeedphrase: CashuUserSeedphrase(seedPhrase: seedPhrase),
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
```

`ndk.destroy()` disposes `wallets`, and `ndk.setBackgrounded(true)` pauses its balance polling.

### add wallets

Create wallets through `wallets.createWallet(...)` so the correct provider validates the required metadata.

```dart
final nwcWallet = wallets.createWallet(
  id: 'alby',
  name: 'Alby',
  type: WalletType.NWC,
  supportedUnits: {'sat'},
  metadata: {
    'nwcUrl': 'nostr+walletconnect://...',
  },
);

await wallets.addWallet(nwcWallet);

final lnurlWallet = wallets.createWallet(
  id: 'tips',
  name: 'Tips',
  type: WalletType.LNURL,
  supportedUnits: {'sat'},
  metadata: {
    'identifier': 'name@example.com',
  },
);

await wallets.addWallet(lnurlWallet);
```

### wallet-specific metadata

- `WalletType.CASHU`
  requires `mintUrl` and `mintInfo`
- `WalletType.NWC`
  requires `nwcUrl`
- `WalletType.LNURL`
  requires `identifier` in `user@domain.com` format

Example for Cashu:

```dart
final mintInfo = await cashu.getMintInfoNetwork(
  mintUrl: 'https://example.mint',
);

final cashuWallet = wallets.createWallet(
  id: 'example-mint',
  name: 'Example Mint',
  type: WalletType.CASHU,
  supportedUnits: mintInfo.supportedUnits,
  metadata: {
    'mintUrl': 'https://example.mint',
    'mintInfo': mintInfo.toJson(),
  },
);

await wallets.addWallet(cashuWallet);
```

## Examples

### balances

```dart
/// all balances from all wallets
final balancesStream = wallets.combinedBalances;

balancesStream.listen((balances) {
  for (final balance in balances) {
    print('${balance.walletId}: ${balance.amount} ${balance.unit}');
  }
});

/// balance of one wallet/unit
final cashuSat = wallets.getBalance('example-mint', 'sat');

/// combined balance across all wallets for one unit
final combinedSat = wallets.getCombinedBalance('sat');
```

### transactions

```dart
/// pending transactions from all wallets
final pendingTransactions = wallets.combinedPendingTransactions;

/// completed / recent transactions from all wallets
final recentTransactions = wallets.combinedRecentTransactions;

/// transactions from storage with optional filters
final transactions = await wallets.combinedTransactions(
  limit: 100,
  offset: 0,
  walletId: 'mywalletId',
  unit: 'sat',
  walletType: WalletType.CASHU,
);

/// streams for one wallet only
wallets.getPendingTransactionsStream('mywalletId').listen(print);
wallets.getRecentTransactionsStream('mywalletId').listen(print);
```

### wallets

```dart
/// stream of all wallets
final walletsStream = wallets.walletsStream;

/// defaults are separate for send and receive
final defaultSendingWallet = wallets.defaultWalletForSending;
final defaultReceivingWallet = wallets.defaultWalletForReceiving;

await wallets.addWallet(myWallet);

wallets.setDefaultWallet('myWalletId');
wallets.setDefaultWalletForSending('myWalletId');
wallets.setDefaultWalletForReceiving('myWalletId');

await wallets.removeWallet('myWalletId');

/// wallets that support a given unit
final walletsSupportingSat = wallets.getWalletsForUnit('sat');
```

### default sending / receiving wallets

The wallet used by generic actions is controlled by two separate defaults:

- `defaultWalletForSending`
  used by `wallets.send(...)`
- `defaultWalletForReceiving`
  used by `wallets.receive(...)`

This is useful if, for example, you want to receive through LNURL but send through NWC or Cashu.

When you add a wallet, NDK tries to set defaults automatically:

- the first wallet that can send becomes the default sending wallet
- the first wallet that can receive becomes the default receiving wallet

You can override that explicitly at any time:

```dart
wallets.setDefaultWalletForSending('alby');
wallets.setDefaultWalletForReceiving('tips');
```

If you want both defaults to point to the same wallet, use:

```dart
wallets.setDefaultWallet('myWalletId');
```

If you call `send()` or `receive()` without passing `walletId`, the corresponding default wallet is used.

```dart
final invoice = await wallets.receive(amountSats: 1000);
final result = await wallets.send(invoice: 'lnbc1...');
```

If no suitable default wallet is set, those generic methods will fail. In that case, either set a default first or pass `walletId` directly.

### actions

Use these if you want a generic wallet API without caring which provider is behind it.

```dart
/// create an invoice using the default receiving wallet
final invoice = await wallets.receive(amountSats: 1000);

/// or choose a specific wallet
final invoice2 = await wallets.receive(
  walletId: 'tips',
  amountSats: 1000,
);

/// pay an invoice using the default sending wallet
final result = await wallets.send(
  invoice: 'lnbc1...',
);

/// or choose a specific wallet
final result2 = await wallets.send(
  walletId: 'alby',
  invoice: 'lnbc1...',
);
```

## Notes

- `zap()` is not implemented yet.
- NWC send/receive support depends on the permissions granted by the connected wallet.
- LNURL wallets are receive-only and do not expose balances or transaction history.
- Cashu wallets can also be discovered automatically from known mints.
- If you need provider-specific features, use `cashu`, `nwc`, or `ndk.lnurl` directly.
