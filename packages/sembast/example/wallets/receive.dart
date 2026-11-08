import 'dart:io';

import 'wallets_setup.dart';

Future<void> main() async {
  final ndk = await setUpWallets();

  try {
    final amountSats = int.parse(Platform.environment['AMOUNT_SATS'] ?? '1000');
    final wallets = await ndk.wallets.getWallets();
    if (wallets.isEmpty) {
      throw StateError('No wallets stored yet.');
    }
    final walletId = Platform.environment['WALLET_ID'] ?? wallets.first.id;

    final invoice = await ndk.wallets.receive(
      walletId: walletId,
      amountSats: amountSats,
    );

    print('Invoice for $amountSats sats:');
    print(invoice);
  } finally {
    await ndk.destroy();
  }
}
