// ignore_for_file: avoid_print

import 'wallets_setup.dart';

Future<void> main() async {
  final setup = await setUpWallets();

  try {
    final wallets = await setup.wallets.getWallets();

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
    await setup.ndk.destroy();
  }
}
