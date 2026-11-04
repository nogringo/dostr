import 'package:ndk/ndk.dart';
import 'package:ndk_cashu/ndk_cashu.dart';
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
  final cashu = Cashu(
    ndk,
    walletsRepo: walletsRepo,
    cashuUserSeedphrase: CashuUserSeedphrase(
      seedPhrase: CashuSeed.generateSeedPhrase(),
    ),
  );
  final wallets = Wallets(
    ndk,
    repository: walletsRepo,
    providers: [
      CashuWalletProvider(cashu),
      NwcWalletProvider(Nwc(ndk)),
      LnurlWalletProvider(ndk.lnurl),
      const Bolt12WalletProvider(),
      LnBitsWalletProvider(),
    ],
  );
  return (ndk: ndk, cashu: cashu, wallets: wallets);
}
