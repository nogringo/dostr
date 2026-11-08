import 'dart:io';

import 'wallets_setup.dart';

Future<void> main() async {
  final ndk = await setUpWallets();

  try {
    final wallets = await ndk.wallets.getWallets();
    if (wallets.isEmpty) {
      print('No wallets stored yet.');
      return;
    }

    final walletId = Platform.environment['WALLET_ID'] ?? wallets.first.id;
    final wallet = wallets.firstWhere(
      (wallet) => wallet.id == walletId,
      orElse: () => throw StateError('Wallet not found: $walletId'),
    );

    final balances = await ndk.wallets
        .getBalancesStream(wallet.id)
        .first
        .timeout(const Duration(seconds: 12));

    if (balances.isEmpty) {
      print('No balances reported for ${wallet.name} (${wallet.id}).');
      return;
    }

    print('Balances for ${wallet.name} (${wallet.id}):');
    for (final balance in balances) {
      print('- ${balance.amount} ${balance.unit}');
    }
  } finally {
    await ndk.destroy();
  }
}
