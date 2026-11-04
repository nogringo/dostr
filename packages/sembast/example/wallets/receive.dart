// ignore_for_file: avoid_print

import 'dart:io';

import 'wallets_setup.dart';

Future<void> main() async {
  final setup = await setUpWallets();

  try {
    final amountSats = int.parse(Platform.environment['AMOUNT_SATS'] ?? '1000');
    final wallets = await setup.wallets.getWallets();
    if (wallets.isEmpty) {
      throw StateError('No wallets stored yet.');
    }
    final walletId = Platform.environment['WALLET_ID'] ?? wallets.first.id;

    final invoice = await setup.wallets.receive(
      walletId: walletId,
      amountSats: amountSats,
    );

    print('Invoice for $amountSats sats:');
    print(invoice);
  } finally {
    await setup.ndk.destroy();
  }
}
