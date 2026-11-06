import 'package:ndk_cashu_protocol/ndk_cashu_protocol.dart';
import '../wallet/providers/cashu/cashu_wallet_transaction.dart';

class CashuSpendingResult {
  final CashuToken token;
  final CashuWalletTransaction transaction;

  CashuSpendingResult({required this.token, required this.transaction});
}
