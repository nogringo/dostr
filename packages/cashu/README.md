# ndk_cashu

[Cashu](https://cashu.space) ecash wallet for [NDK](https://pub.dev/packages/ndk): mint, melt, send and receive tokens, deterministic secrets and restore from a seed phrase.

> Experimental, do not use in production. If the storage is lost, funds are lost.

For the protocol alone, without a wallet or Nostr, use [ndk_cashu_protocol](../cashu_protocol/): this package re-exports it.

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_cashu: ^0.1.0
```

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_cashu/ndk_cashu.dart';

final ndk = Ndk.defaultConfig();

// generate once, store securely: the seed phrase gives full access to the funds
final seedPhrase = CashuSeed.generateSeedPhrase();

final cashu = Cashu(
  ndk,
  cashuUserSeedphrase: CashuUserSeedphrase(seedPhrase: seedPhrase),
);

final draft = await cashu.initiateFund(
  mintUrl: 'https://mint.example.com',
  amount: 100,
  unit: 'sat',
  method: 'bolt11',
);
print('pay ${draft.qoute!.request}');
await for (final tx in cashu.retrieveFunds(draftTransaction: draft)) {
  print(tx.state);
}
```

## Storage

Proofs, keysets, mint infos and secret counters go to a `CashuStorage`. Without `storage`, `Cashu` uses the NDK cache when it implements `CashuStorage` (`ndk_objectbox`, `ndk_drift`, `ndk_sembast` and `ndk_sqlite3` do), and an in memory `MemCashuStorage` otherwise.

Pending quotes are recorded in a `WalletsRepo` from [ndk_wallets](../wallets/): pass `walletsRepo`, ideally the same one as `Wallets`. `CashuWalletProvider(cashu)` plugs Cashu into `Wallets`.
