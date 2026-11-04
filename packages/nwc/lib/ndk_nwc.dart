/// Nostr Wallet Connect (NIP-47) for NDK.
///
/// ```dart
/// final nwc = Nwc(ndk);
/// final connection = await nwc.connect(nwcUri);
/// ```
library;

export 'package:ndk_wallets/ndk_wallets.dart'
    show NwcResponse, PayInvoiceResponse, PayResponse, ReceiveResponse;

export 'src/domain_layer/entities/wallet/providers/nwc/nwc_wallet.dart';
export 'src/domain_layer/entities/wallet/providers/nwc/nwc_wallet_provider.dart';
export 'src/domain_layer/entities/wallet/providers/nwc/nwc_wallet_transaction.dart';
export 'src/domain_layer/entities/wallet/providers/nwc/nwc_wallet_types.dart';
export 'src/domain_layer/usecases/nwc/consts/bitcoin_network.dart';
export 'src/domain_layer/usecases/nwc/consts/budget_renewal_period.dart';
export 'src/domain_layer/usecases/nwc/consts/error_code.dart';
export 'src/domain_layer/usecases/nwc/consts/nwc_extension.dart';
export 'src/domain_layer/usecases/nwc/consts/nwc_kind.dart';
export 'src/domain_layer/usecases/nwc/consts/nwc_method.dart';
export 'src/domain_layer/usecases/nwc/consts/transaction_type.dart';
export 'src/domain_layer/usecases/nwc/nostr_wallet_connect_uri.dart';
export 'src/domain_layer/usecases/nwc/nwc.dart';
export 'src/domain_layer/usecases/nwc/nwc_connection.dart';
export 'src/domain_layer/usecases/nwc/nwc_notification.dart';
export 'src/domain_layer/usecases/nwc/requests/cancel_hold_invoice.dart';
export 'src/domain_layer/usecases/nwc/requests/get_balance.dart';
export 'src/domain_layer/usecases/nwc/requests/get_budget.dart';
export 'src/domain_layer/usecases/nwc/requests/get_info.dart';
export 'src/domain_layer/usecases/nwc/requests/list_transactions.dart';
export 'src/domain_layer/usecases/nwc/requests/lookup_invoice.dart';
export 'src/domain_layer/usecases/nwc/requests/make_hold_invoice.dart';
export 'src/domain_layer/usecases/nwc/requests/make_invoice.dart';
export 'src/domain_layer/usecases/nwc/requests/multi_pay_invoice.dart';
export 'src/domain_layer/usecases/nwc/requests/multi_pay_keysend.dart';
export 'src/domain_layer/usecases/nwc/requests/nwc_request.dart';
export 'src/domain_layer/usecases/nwc/requests/pay.dart';
export 'src/domain_layer/usecases/nwc/requests/pay_invoice.dart';
export 'src/domain_layer/usecases/nwc/requests/pay_keysend.dart';
export 'src/domain_layer/usecases/nwc/requests/receive.dart';
export 'src/domain_layer/usecases/nwc/requests/settle_hold_invoice.dart';
export 'src/domain_layer/usecases/nwc/responses/get_balance_response.dart';
export 'src/domain_layer/usecases/nwc/responses/get_budget_response.dart';
export 'src/domain_layer/usecases/nwc/responses/get_info_response.dart';
export 'src/domain_layer/usecases/nwc/responses/list_transactions_response.dart';
export 'src/domain_layer/usecases/nwc/responses/lookup_invoice_response.dart';
export 'src/domain_layer/usecases/nwc/responses/make_invoice_response.dart';
export 'src/domain_layer/usecases/nwc/tlv_record.dart';
export 'src/domain_layer/usecases/nwc/zap_response.dart';
