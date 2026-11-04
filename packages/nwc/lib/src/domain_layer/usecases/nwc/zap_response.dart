import 'dart:async';

import 'package:ndk/ndk.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

/// zap response
class ZapResponse {
  NdkResponse? zapReceiptResponse;
  PayInvoiceResponse? payInvoiceResponse;
  String? error;
  final _receiptCompleter = Completer<ZapReceipt?>();

  /// the validated zap receipt
  Future<ZapReceipt?> get zapReceipt {
    if (zapReceiptResponse == null) {
      return Future.value(null);
    }
    return _receiptCompleter.future;
  }

  /// emit the receipt
  void emitReceipt(ZapReceipt? receipt) {
    _receiptCompleter.complete(receipt);
  }

  ///
  ZapResponse({this.zapReceiptResponse, this.payInvoiceResponse, this.error});

  set receiptResponse(NdkResponse receiptResponse) {
    zapReceiptResponse = receiptResponse;
  }
}
