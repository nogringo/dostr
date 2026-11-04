import 'dart:core';

import '../../../domain_layer/entities/wallet/wallet.dart';
import '../../../domain_layer/entities/wallet/wallet_transaction.dart';
import '../../../domain_layer/entities/wallet/wallet_type.dart';
import '../../../domain_layer/repositories/wallets_repo.dart';

class StubWalletsRepo extends WalletsRepo {
  @override
  Future<List<WalletTransaction>> getTransactions({
    int? limit,
    int? offset,
    String? walletId,
    String? unit,
    WalletType? walletType,
  }) {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }

  @override
  Future<void> saveTransactions(List<WalletTransaction> transactions) {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }

  @override
  Future<void> removeTransactions(List<String>? transactionIds) {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }

  @override
  Future<List<Wallet>> getWallets({List<String>? ids}) {
    return Future.value([]);
  }

  @override
  Future<void> removeWallet(String id) {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }

  @override
  Future<void> storeWallet(Wallet wallet) {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }

  @override
  String? getDefaultWalletIdForReceiving() {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }

  @override
  String? getDefaultWalletIdForSending() {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }

  @override
  void setDefaultWalletForReceiving(String? walletId) {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }

  @override
  void setDefaultWalletForSending(String? walletId) {
    throw UnimplementedError(
      "pass a proper WalletsRepo to Cashu and Wallets to use this method",
    );
  }
}
