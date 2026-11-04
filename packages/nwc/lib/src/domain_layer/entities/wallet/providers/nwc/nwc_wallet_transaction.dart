import 'package:ndk_wallets/ndk_wallets.dart';

class NwcWalletTransaction extends WalletTransaction {
  NwcWalletTransaction({
    required super.id,
    required super.walletId,
    required super.changeAmount,
    required super.unit,
    required super.walletType,
    required super.state,
    required super.metadata,
    super.completionMsg,
    super.transactionDate,
    super.initiatedDate,
  });

  /// Rebuilds a transaction stored by a `WalletsRepo`.
  static NwcWalletTransaction fromStorage({
    required String id,
    required String walletId,
    required int changeAmount,
    required String unit,
    required WalletType walletType,
    required WalletTransactionState state,
    required Map<String, dynamic> metadata,
    String? completionMsg,
    int? transactionDate,
    int? initiatedDate,
  }) => NwcWalletTransaction(
    id: id,
    walletId: walletId,
    changeAmount: changeAmount,
    unit: unit,
    walletType: walletType,
    state: state,
    metadata: metadata,
    completionMsg: completionMsg,
    transactionDate: transactionDate,
    initiatedDate: initiatedDate,
  );
}
