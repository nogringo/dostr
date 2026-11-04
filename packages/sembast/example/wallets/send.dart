// ignore_for_file: avoid_print

import 'dart:io';

import 'wallets_setup.dart';

Future<void> main() async {
  final payment = Platform.environment['PAYMENT']!;
  final amountSats = int.parse(Platform.environment['AMOUNT'] ?? '1000');

  final setup = await setUpWallets();

  try {
    final wallets = await setup.wallets.getWallets();
    if (wallets.isEmpty) {
      throw StateError('No wallets stored yet.');
    }

    final walletId = Platform.environment['WALLET_ID'] ?? wallets.first.id;

    final result = await setup.wallets.payBip321(
      walletId: walletId,
      payment: payment,
      amountMsat: amountSats * 1000,
    );

    print('Payment result:');
    print('- preimage: ${result.preimage}');
    print('- payerProof: ${result.payerProof}');
    print('- fees paid: ${result.feesPaid / 1000} sats');
    if (result.errorCode != null || result.errorMessage != null) {
      print('- error code: ${result.errorCode}');
      print('- error message: ${result.errorMessage}');
    }
  } finally {
    await setup.ndk.destroy();
  }
}
