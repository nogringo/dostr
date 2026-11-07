/// Wallets for NDK: one API over Cashu, NWC, LNURL, BOLT12 and LNbits.
///
/// ```dart
/// final wallets = Wallets(
///   repository: MemWalletsRepo(),
///   providers: [LnurlWalletProvider(lnurl)],
/// );
/// ```
library;

export 'src/data_layer/repositories/wallets/mem_wallets_repo.dart';
export 'src/data_layer/repositories/wallets/wallets_repo_stub.dart';
export 'src/domain_layer/entities/wallet/bip321.dart';
export 'src/domain_layer/entities/wallet/providers/bolt12/bolt12_wallet.dart';
export 'src/domain_layer/entities/wallet/providers/bolt12/bolt12_wallet_provider.dart';
export 'src/domain_layer/entities/wallet/providers/lnbits/lnbits_wallet.dart';
export 'src/domain_layer/entities/wallet/providers/lnbits/lnbits_wallet_provider.dart';
export 'src/domain_layer/entities/wallet/providers/lnurl/lnurl_wallet.dart';
export 'src/domain_layer/entities/wallet/providers/lnurl/lnurl_wallet_provider.dart';
export 'src/domain_layer/entities/wallet/responses/nwc_response.dart';
export 'src/domain_layer/entities/wallet/responses/pay_invoice_response.dart';
export 'src/domain_layer/entities/wallet/responses/pay_response.dart';
export 'src/domain_layer/entities/wallet/responses/receive_response.dart';
export 'src/domain_layer/entities/wallet/wallet.dart';
export 'src/domain_layer/entities/wallet/wallet_balance.dart';
export 'src/domain_layer/entities/wallet/wallet_factory.dart';
export 'src/domain_layer/entities/wallet/wallet_provider.dart';
export 'src/domain_layer/entities/wallet/wallet_transaction.dart';
export 'src/domain_layer/entities/wallet/wallet_type.dart';
export 'src/domain_layer/repositories/wallets_repo.dart';
export 'src/domain_layer/usecases/wallets/wallets.dart';
