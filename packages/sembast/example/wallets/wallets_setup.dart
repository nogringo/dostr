import 'package:ndk/ndk.dart';
import 'package:ndk_sembast/ndk_sembast.dart';

/// NDK with every wallet type, wallets stored in the Sembast file [filename].
Future<Ndk> setUpWallets({String filename = 'wallets_db.db'}) async {
  final walletsRepo = await SembastWalletsRepo.create(filename: filename);
  return Ndk(
    NdkConfig(
      cache: MemCacheManager(),
      walletsRepo: walletsRepo,
      eventVerifier: Bip340EventVerifier(),
      bootstrapRelays: const [],
      cashuUserSeedphrase: CashuUserSeedphrase(
        seedPhrase: CashuSeed.generateSeedPhrase(),
      ),
    ),
  );
}
