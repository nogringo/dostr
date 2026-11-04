import 'package:ndk_wallets/ndk_wallets.dart';

import 'cashu_wallet.dart';
import 'cashu_wallet_transaction.dart';

/// Lets wallets repositories rebuild stored Cashu wallets and transactions.
/// [Cashu] and [CashuWalletProvider] call it, call it yourself to read a
/// repository before creating either.
void registerCashuWalletTypes() {
  WalletFactory.registerType(WalletType.CASHU, CashuWallet.fromStorage);
  WalletTransaction.registerType(
    WalletType.CASHU,
    CashuWalletTransaction.fromStorage,
  );
}
