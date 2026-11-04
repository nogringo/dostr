# ndk_sembast

A [Sembast](https://pub.dev/packages/sembast) cache manager and wallets repository for [NDK](https://pub.dev/packages/ndk), in pure Dart.

- `SembastCacheManager` persists the NDK cache and Cashu data (`CashuStorage` from `ndk_cashu`), in a database file on native platforms and in IndexedDB on the web.
- `SembastWalletsRepo` persists wallets for `Wallets` and `Cashu` (`ndk_wallets`, `ndk_cashu`). `SembastWalletsRepo.create` opens a database file, so it is native only; on the web, pass an opened Sembast database to the constructor.
- No Flutter required.

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_sembast/ndk_sembast.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

// databasePath is required on native platforms and ignored on the web.
final cache = await SembastCacheManager.create(databasePath: '/path/to/db');
final walletsRepo = await SembastWalletsRepo.create(filename: 'wallets.db');

final ndk = Ndk(
  NdkConfig(cache: cache, eventVerifier: Bip340EventVerifier()),
);

// Cashu proofs go to the cache, which implements CashuStorage.
final cashu = Cashu(ndk, walletsRepo: walletsRepo);
final wallets = Wallets(
  ndk,
  repository: walletsRepo,
  providers: [CashuWalletProvider(cashu), LnurlWalletProvider(ndk.lnurl)],
);

// ...

await ndk.destroy();
await cache.close();
await walletsRepo.close();
```

More in [example/](example/).
