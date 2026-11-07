# ndk_wallets

One wallet API for [NDK](https://pub.dev/packages/ndk): balances, transaction history, send and receive across Cashu, NWC, LNURL, BOLT12 and LNbits wallets.

LNURL, BOLT12 and LNbits providers are included. Cashu and NWC providers come with [ndk_cashu](../cashu/) and [ndk_nwc](../nwc/).

It does not depend on `ndk`.

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_wallets: ^0.1.0
  ndk_cashu: ^0.1.0 # Cashu wallets
  ndk_nwc: ^0.1.0 # NWC wallets
```

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_nwc/ndk_nwc.dart';
import 'package:ndk_sembast/ndk_sembast.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

final walletsRepo = await SembastWalletsRepo.create(filename: 'wallets.db');
final ndk = Ndk.defaultConfig();

// built as their READMEs show, with the same walletsRepo for Cashu
final Cashu cashu = ...;
final Nwc nwc = ...;

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

final wallet = wallets.createWallet(
  id: 'alby',
  name: 'Alby',
  type: WalletType.NWC,
  supportedUnits: {'sat'},
  metadata: {'nwcUrl': 'nostr+walletconnect://...'},
);
await wallets.addWallet(wallet);

final result = await wallets.send(invoice: 'lnbc1...');

// also disposes wallets, through the lifecycle hooks
await ndk.destroy();
```

`WalletsRepo.fromCache(ndk.config.cache)` stores wallets in the NDK cache when it implements `WalletsRepo` (`ndk_objectbox`, `ndk_drift` and `ndk_sqlite3` do). On Flutter, `FlutterSecureStorageWalletsRepo` from `ndk_flutter` keeps wallets in secure storage. `setBackgrounded` pauses LNbits balance polling, and `dispose` releases the wallets.
