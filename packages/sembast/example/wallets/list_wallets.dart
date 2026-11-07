// ignore_for_file: avoid_print

import 'wallets_setup.dart';

Future<void> main() async {
  final ndk = await setUpWallets();

  try {
    final wallets = await ndk.wallets.getWallets();

    if (wallets.isEmpty) {
      print('No wallets stored yet.');
      return;
    }

    print('Wallets (${wallets.length}):');
    for (final wallet in wallets) {
      print(
        '- id=${wallet.id} name=${wallet.name} '
        'type=${wallet.type.value} units=${wallet.supportedUnits.join(',')}',
      );
    }
  } finally {
    await ndk.destroy();
  }
}
