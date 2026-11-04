import 'wallet_type.dart';

/// Rebuilds a stored transaction of one [WalletType], see
/// [WalletTransaction.registerType].
typedef WalletTransactionFromStorage =
    WalletTransaction Function({
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
    });

abstract class WalletTransaction {
  final String id;
  final String walletId;

  /// positive for incoming, negative for outgoing
  final int changeAmount;
  final String unit;
  final WalletType walletType;
  final WalletTransactionState state;
  final String? completionMsg;

  /// Date in milliseconds since epoch
  int? transactionDate;

  /// Date in milliseconds since epoch
  int? initiatedDate;

  /// metadata to store additional information for the specific transaction type
  final Map<String, dynamic> metadata;

  WalletTransaction({
    required this.id,
    required this.walletId,
    required this.changeAmount,
    required this.unit,
    required this.walletType,
    required this.state,
    required this.metadata,
    this.completionMsg,
    this.transactionDate,
    this.initiatedDate,
  });

  static final Map<WalletType, WalletTransactionFromStorage> _fromStorage = {
    WalletType.LNURL: LnurlWalletTransaction.new,
    WalletType.BOLT12: LnurlWalletTransaction.new,
    WalletType.LNBITS: LnurlWalletTransaction.new,
  };

  /// Registers how [toTransactionType] rebuilds transactions of [type].
  /// ndk_cashu and ndk_nwc register theirs when their usecase or wallet
  /// provider is created.
  static void registerType(
    WalletType type,
    WalletTransactionFromStorage fromStorage,
  ) {
    _fromStorage[type] = fromStorage;
  }

  /// constructs the concrete wallet type based on the type string \
  /// metadata is used to provide additional information required for the wallet type
  static WalletTransaction toTransactionType({
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
  }) {
    final fromStorage = _fromStorage[walletType];
    if (fromStorage == null) {
      throw StateError(
        'No transaction type registered for $walletType wallets, '
        'create its usecase or wallet provider first',
      );
    }
    return fromStorage(
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
}

class LnurlWalletTransaction extends WalletTransaction {
  LnurlWalletTransaction({
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
}

enum WalletTransactionState {
  /// pending states

  /// draft requires user confirmation
  draft('DRAFT'),

  /// payment is in flight
  pending('PENDING'),

  /// done states
  /// transaction went through
  completed('SUCCESS'),

  /// canceld by user - usually a canceld draft, or not sufficient funds
  canceled('CANCELED'),

  /// transaction failed
  failed('FAILED');

  bool get isPending => this == draft || this == pending;

  bool get isDone => this == completed || this == canceled || this == failed;

  final String value;

  const WalletTransactionState(this.value);

  factory WalletTransactionState.fromValue(String value) {
    return WalletTransactionState.values.firstWhere(
      (state) => state.value == value,
      orElse: () =>
          throw ArgumentError('Invalid pending transaction state: $value'),
    );
  }

  @override
  String toString() {
    return value;
  }
}
