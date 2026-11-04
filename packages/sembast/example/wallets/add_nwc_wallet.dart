// ignore_for_file: avoid_print

import 'dart:io';

import 'package:ndk_nwc/ndk_nwc.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

import 'wallets_setup.dart';

Future<void> main() async {
  final nwcUri = Platform.environment['NWC_URI']!;
  final walletName = Platform.environment['WALLET_NAME'] ?? 'My NWC Wallet';

  final examplesDir = Directory.current.absolute;
  final dbPath = '${examplesDir.path}/wallets_db.db';
  final setup = await setUpWallets(filename: dbPath);

  try {
    NostrWalletConnectUri.parseConnectionUri(nwcUri);

    final wallet = setup.wallets.createWallet(
      id: 'wallet_${DateTime.now().microsecondsSinceEpoch}',
      name: walletName,
      type: WalletType.NWC,
      supportedUnits: {'sat'},
      metadata: {'nwcUrl': nwcUri},
    );

    await setup.wallets.addWallet(wallet);

    print('Added ${wallet.name}.');
    print('');
    final wallets = await setup.wallets.getWallets();
    print('Wallets (${wallets.length}):');
    for (final wallet in wallets) {
      print(
        '- ${wallet.name} (${wallet.type.value}) id=${wallet.id} '
        'units=${wallet.supportedUnits.join(',')}',
      );
    }
  } finally {
    await setup.ndk.destroy();
  }
}
