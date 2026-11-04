import 'package:ndk_wallets/ndk_wallets.dart';

import '../../../cashu/cashu_keyset.dart';
import '../../../cashu/cashu_quote.dart';
import '../../../cashu/cashu_quote_melt.dart';

class CashuWalletTransaction extends WalletTransaction {
  String mintUrl;
  String? note;
  String? method;
  CashuQuote? qoute;
  CashuQuoteMelt? qouteMelt;
  List<CahsuKeyset>? usedKeysets;

  String? token;

  List<String>? proofPubKeys;

  CashuWalletTransaction({
    required super.id,
    required super.walletId,
    required super.changeAmount,
    required super.unit,
    required super.walletType,
    required super.state,
    required this.mintUrl,
    super.completionMsg,
    super.transactionDate,
    super.initiatedDate,
    this.note,
    this.method,
    this.qoute,
    this.qouteMelt,
    this.usedKeysets,
    this.token,
    this.proofPubKeys,
    Map<String, dynamic>? metadata,
  }) : super(
         metadata:
             metadata ??
             {
               'mintUrl': mintUrl,
               'note': note,
               'method': method,
               'qoute': qoute?.toJson(),
               'qouteMelt': qouteMelt?.toJson(),
               'usedKeyset': usedKeysets?.map((k) => k.toJson()).toList(),
               'token': token,
               'proofPubKeys': proofPubKeys,
             },
       );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashuWalletTransaction &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          token == other.token;

  @override
  int get hashCode => id.hashCode;

  CashuWalletTransaction copyWith({
    String? id,
    String? walletId,
    int? changeAmount,
    String? unit,
    WalletType? walletType,
    WalletTransactionState? state,
    String? mintUrl,
    String? note,
    String? method,
    CashuQuote? qoute,
    CashuQuoteMelt? qouteMelt,
    List<CahsuKeyset>? usedKeysets,
    int? transactionDate,
    int? initiatedDate,
    String? completionMsg,
    String? token,
    List<String>? proofPubKeys,
  }) {
    return CashuWalletTransaction(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      changeAmount: changeAmount ?? this.changeAmount,
      unit: unit ?? this.unit,
      walletType: walletType ?? this.walletType,
      state: state ?? this.state,
      mintUrl: mintUrl ?? this.mintUrl,
      note: note ?? this.note,
      method: method ?? this.method,
      qoute: qoute ?? this.qoute,
      qouteMelt: qouteMelt ?? this.qouteMelt,
      usedKeysets: usedKeysets ?? this.usedKeysets,
      transactionDate: transactionDate ?? this.transactionDate,
      initiatedDate: initiatedDate ?? this.initiatedDate,
      completionMsg: completionMsg ?? this.completionMsg,
      token: token ?? this.token,
      proofPubKeys: proofPubKeys ?? this.proofPubKeys,
    );
  }

  /// Rebuilds a transaction stored by a `WalletsRepo`.
  static CashuWalletTransaction fromStorage({
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
    return CashuWalletTransaction(
      id: id,
      walletId: walletId,
      changeAmount: changeAmount,
      unit: unit,
      walletType: walletType,
      state: state,
      mintUrl: metadata['mintUrl'] as String,
      completionMsg: completionMsg,
      transactionDate: transactionDate,
      initiatedDate: initiatedDate,
      note: metadata['note'] as String?,
      method: metadata['method'] as String?,
      qoute: metadata['qoute'] != null
          ? CashuQuote.fromJson(metadata['qoute'] as Map<String, dynamic>)
          : null,
      qouteMelt: metadata['qouteMelt'] != null
          ? CashuQuoteMelt.fromJson(
              metadata['qouteMelt'] as Map<String, dynamic>,
            )
          : null,
      usedKeysets: metadata['usedKeyset'] != null
          ? (metadata['usedKeyset'] as List<dynamic>)
                .map((k) => CahsuKeyset.fromJson(k as Map<String, dynamic>))
                .toList()
          : null,
      token: metadata['token'] as String?,
      proofPubKeys: (metadata['proofPubKeys'] as List<dynamic>?)
          ?.map((p) => p.toString())
          .toList(),
    );
  }
}
