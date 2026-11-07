# ndk_cashu

[Cashu](https://cashu.space) ecash wallet for [NDK](https://pub.dev/packages/ndk): mint, melt, send and receive tokens, deterministic secrets and restore from a seed phrase.

> Experimental, do not use in production. If the storage is lost, funds are lost.

For the protocol alone, without a wallet or Nostr, use [ndk_cashu_protocol](../cashu_protocol/): this package re-exports it.

It does not depend on `ndk`: mint discovery asks you how to query the relays. NDK exposes it as `ndk.cashu`, with the seed phrase of `NdkConfig.cashuUserSeedphrase` and the wallets of `NdkConfig.walletsRepo`: build it yourself, as below, only to wire it differently.

## Install

```yaml
dependencies:
  http: ^1.6.0
  ndk: ^0.11.0-dev.2
  ndk_cashu: ^0.1.0
  ndk_http: ^0.1.0
```

## Usage

```dart
import 'package:http/http.dart' as http;
import 'package:ndk/ndk.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_http/ndk_http.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

final ndk = Ndk.defaultConfig();

// generate once, store securely: the seed phrase gives full access to the funds
final seedPhrase = CashuSeed.generateSeedPhrase();

final cashuHttp = NdkHttp(http.Client());
final cashu = Cashu(
  cashuRepo: CashuRepoImpl(client: cashuHttp),
  walletsRepo: MemWalletsRepo(),
  storage: MemCashuStorage(),
  cashuKeyDerivation: DartCashuKeyDerivation(),
  mintRecommendations: CashuMintRecommendations(
    query: (filter, {required relays, required timeout}) => ndk.requests
        .query(filter: filter, explicitRelays: relays, timeout: timeout)
        .future,
  ),
  cashuUserSeedphrase: CashuUserSeedphrase(seedPhrase: seedPhrase),
);
ndk.addLifecycleHooks(onDestroy: () async => cashuHttp.abortPending());

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

Proofs, keysets, mint infos and secret counters go to `storage`, a `CashuStorage`: the NDK cache when it implements it (`ndk_objectbox`, `ndk_drift`, `ndk_sembast` and `ndk_sqlite3` do), or an in memory `MemCashuStorage`.

Pending quotes are recorded in `walletsRepo`, a `WalletsRepo` from [ndk_wallets](../wallets/), ideally the same one as `Wallets`. `CashuWalletProvider(cashu)` plugs Cashu into `Wallets`.

`mintRecommendations` answers `discoverMintRecommendations` from NIP-87 announcements and reviews. Without it, only that method fails.
