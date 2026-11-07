import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

class _RecordingWalletsRepo extends MemWalletsRepo {
  int reads = 0;

  @override
  Future<List<Wallet>> getWallets({List<String>? ids}) {
    reads++;
    return super.getWallets(ids: ids);
  }
}

void main() {
  test('each add-on usecase is built once', () async {
    final ndk = Ndk.emptyBootstrapRelaysConfig();
    addTearDown(ndk.destroy);

    expect(ndk.nwc, same(ndk.nwc));
    expect(ndk.cashu, same(ndk.cashu));
    expect(ndk.wallets, same(ndk.wallets));
    expect(ndk.blossom, same(ndk.blossom));
    expect(ndk.files, same(ndk.files));
    expect(ndk.dms, same(ndk.dms));
    expect(ndk.software, same(ndk.software));
    expect(ndk.ta, same(ndk.trustedAssertions));
  });

  test(
    'wallets and cashu use the wallets repo and seed phrase of the config',
    () async {
      final walletsRepo = _RecordingWalletsRepo();
      final ndk = Ndk(
        NdkConfig(
          cache: MemCacheManager(),
          eventVerifier: Bip340EventVerifier(),
          bootstrapRelays: const [],
          walletsRepo: walletsRepo,
          cashuUserSeedphrase: CashuUserSeedphrase(
            seedPhrase: CashuSeed.generateSeedPhrase(),
          ),
        ),
      );
      addTearDown(ndk.destroy);

      await ndk.wallets.getWallets();

      expect(walletsRepo.reads, greaterThan(0));
      expect(ndk.cashu.getCashuSeed().isSeedPhraseSet, isTrue);
    },
  );

  test('setBackgrounded and destroy reach the wallets once built', () async {
    final ndk = Ndk.emptyBootstrapRelaysConfig();
    await ndk.wallets.getWallets();

    await ndk.setBackgrounded(true);
    await ndk.setBackgrounded(false);
    await ndk.destroy();
  });
}
