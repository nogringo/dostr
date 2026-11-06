import 'dart:async';

import 'package:ndk_core/shared/logger/logger.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import '../../entities/request_response.dart';
import 'package:ndk_signer/ndk_signer.dart';
import '../lnurl/lnurl.dart';
import '../requests/requests.dart';
import 'invoice_response.dart';
import 'zap_receipt.dart';
import 'zap_request.dart';

/// Zaps
class Zaps {
  final Requests _requests;
  final Lnurl _lnurl;

  /// .
  Zaps({required Requests requests, required Lnurl lnurl})
    : _requests = requests,
      _lnurl = lnurl;

  /// creates an invoice with an optional zap request encoded if signer, pubKey & relays are non empty
  Future<InvoiceResponse?> fetchInvoice({
    required String lud16Link,
    required int amountSats,
    ZapRequest? zapRequest,
    String? comment,
  }) async {
    final lnurlResponse = await _lnurl.getLnurlResponse(lud16Link);
    if (lnurlResponse == null) {
      return null;
    }

    try {
      return await _lnurl.fetchInvoice(
        lnurlResponse: lnurlResponse,
        amountSats: amountSats,
        zapRequest: zapRequest,
      );
    } catch (e) {
      Logger.log.d(() => e);
      return null;
    }
  }

  /// creates a zap request
  Future<ZapRequest> createZapRequest({
    required int amountSats,
    required EventSigner signer,
    required String pubKey,
    String? eventId,
    String? addressableId,
    String? comment,
    required Iterable<String> relays,
    String? pollOption,
  }) async {
    if (amountSats < 0) {
      throw ArgumentError("amount cannot be < 0");
    }
    final amount = amountSats * 1000;

    var tags = [
      ["relays", ...relays],
      ["amount", amount.toString()],
      ["p", pubKey],
    ];
    if (eventId != null) {
      tags.add(["e", eventId]);
    }
    if (addressableId != null) {
      tags.add(["a", addressableId]);
    }
    if (pollOption != null) {
      tags.add(["poll_option", pollOption]);
    }
    final zapRequestEvent = ZapRequest(
      pubKey: signer.getPublicKey(),
      tags: tags,
      content: comment ?? '',
    );
    final signedEvent = await signer.sign(zapRequestEvent);

    final sigendZapRequest = ZapRequest.nip01Event(event: signedEvent);
    return sigendZapRequest;
  }

  /// fetch all zap receipts matching given pubKey and optional event id, in sats
  Stream<ZapReceipt> fetchZappedReceipts({
    required String pubKey,
    String? eventId,
    String? addressableId,
    Duration? timeout,
  }) {
    NdkResponse? response = _requests.query(
      timeout: timeout ?? Duration(seconds: 10),
      filters: [
        Filter(
          kinds: [ZapReceipt.kKind],
          eTags: eventId != null ? [eventId] : null,
          aTags: addressableId != null ? [addressableId] : null,
          pTags: [pubKey],
        ),
      ],
    );
    // TODO how to check validity of zap receipts without nostrPubKey and recipientLnurl????
    return response.stream.map((event) => ZapReceipt.fromEvent(event));
    // List<Nip01Event> events = await response.future;
    // return events.map((event) => ZapReceipt.fromEvent(event)).toList();
  }

  /// fetch all zap receipts matching given pubKey and optional event id, in sats
  NdkResponse subscribeToZapReceipts({
    required String pubKey,
    String? eventId,
    String? addressableId,
  }) {
    NdkResponse? response = _requests.subscription(
      filters: [
        Filter(
          kinds: [ZapReceipt.kKind],
          eTags: eventId != null ? [eventId] : null,
          aTags: addressableId != null ? [addressableId] : null,
          pTags: [pubKey],
        ),
      ],
    );
    return response;
  }
}
