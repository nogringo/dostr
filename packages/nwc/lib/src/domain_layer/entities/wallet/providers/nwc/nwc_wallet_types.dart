import 'package:ndk_wallets/ndk_wallets.dart';

import 'nwc_wallet.dart';
import 'nwc_wallet_transaction.dart';

/// Lets wallets repositories rebuild stored NWC wallets and transactions.
/// [Nwc] and [NwcWalletProvider] call it, call it yourself to read a
/// repository before creating either.
void registerNwcWalletTypes() {
  WalletFactory.registerType(WalletType.NWC, NwcWallet.fromStorage);
  WalletTransaction.registerType(
    WalletType.NWC,
    NwcWalletTransaction.fromStorage,
  );
}
