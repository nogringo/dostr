import 'dart:io';

import 'package:ndk_wallets/ndk_wallets.dart';

import 'wallets_setup.dart';

Future<void> main() async {
  final mintUrl = Platform.environment['MINT_URL']!;
  final walletName = Platform.environment['WALLET_NAME'] ?? 'My Cashu Wallet';

  final ndk = await setUpWallets();

  try {
    final mintInfo = await ndk.cashu.getMintInfoNetwork(mintUrl: mintUrl);

    final wallet = ndk.wallets.createWallet(
      id: 'wallet_${DateTime.now().microsecondsSinceEpoch}',
      name: walletName,
      type: WalletType.CASHU,
      supportedUnits: mintInfo.supportedUnits.isEmpty
          ? {'sat'}
          : mintInfo.supportedUnits,
      metadata: {'mintUrl': mintUrl, 'mintInfo': mintInfo.toJson()},
    );

    await ndk.wallets.addWallet(wallet);

    print('Added ${wallet.name}.');
    print('');
    final wallets = await ndk.wallets.getWallets();
    print('Wallets (${wallets.length}):');
    for (final wallet in wallets) {
      print(
        '- ${wallet.name} (${wallet.type.value}) id=${wallet.id} '
        'units=${wallet.supportedUnits.join(',')}',
      );
    }
  } finally {
    await ndk.destroy();
  }
}
