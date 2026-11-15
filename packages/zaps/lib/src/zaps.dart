import 'dart:async';

import 'package:dostr_core/dostr_core.dart' show Logger;
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

import 'invoice_response.dart';
import 'lnurl.dart';
import 'zap_receipt.dart';
import 'zap_request.dart';

/// The events relays hold for [filter], as they arrive. The stream ends once
/// the relays are done or [timeout] runs out.
typedef ZapsQuery =
    Stream<Nip01Event> Function(Filter filter, {required Duration timeout});

/// A live subscription: the [events] it receives, and [close] to end it.
typedef ZapsSubscription = ({
  Stream<Nip01Event> events,
  Future<void> Function() close,
});

/// Opens a live subscription to [filter].
typedef ZapsSubscribe = ZapsSubscription Function(Filter filter);

/// Zaps
class Zaps {
  final ZapsQuery _query;
  final ZapsSubscribe _subscribe;
  final Lnurl _lnurl;

  /// [query] answers [fetchZappedReceipts], [subscribe]
  /// [subscribeToZapReceipts] and [lnurl] the invoices.
  Zaps({
    required ZapsQuery query,
    required ZapsSubscribe subscribe,
    required Lnurl lnurl,
  }) : _query = query,
       _subscribe = subscribe,
       _lnurl = lnurl;

  /// creates an invoice with an optional zap request encoded if signer, pubkey & relays are non empty
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
        comment: comment,
      );
    } catch (e) {
      Logger.log.d(() => e);
      return null;
    }
  }

  /// creates a zap request
  Future<ZapRequest> createZapRequest({
    required int amountSats,
    required NostrSigner signer,
    required String pubkey,
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
      ["p", pubkey],
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
      pubkey: signer.getPublicKey(),
      tags: tags,
      content: comment ?? '',
    );
    final signedEvent = await signer.sign(zapRequestEvent);

    final sigendZapRequest = ZapRequest.nip01Event(event: signedEvent);
    return sigendZapRequest;
  }

  /// fetch all zap receipts matching given pubkey and optional event id, in sats
  Stream<ZapReceipt> fetchZappedReceipts({
    required String pubkey,
    String? eventId,
    String? addressableId,
    Duration? timeout,
  }) {
    final events = _query(
      _receiptsFilter(pubkey, eventId, addressableId),
      timeout: timeout ?? const Duration(seconds: 10),
    );
    // TODO how to check validity of zap receipts without nostrPubkey and recipientLnurl????
    return events.map((event) => ZapReceipt.fromEvent(event));
  }

  /// subscribe to the zap receipt events matching given pubkey and optional
  /// event id, until the subscription is closed
  ZapsSubscription subscribeToZapReceipts({
    required String pubkey,
    String? eventId,
    String? addressableId,
  }) => _subscribe(_receiptsFilter(pubkey, eventId, addressableId));

  static Filter _receiptsFilter(
    String pubkey,
    String? eventId,
    String? addressableId,
  ) => Filter(
    kinds: [ZapReceipt.kKind],
    eTags: eventId != null ? [eventId] : null,
    aTags: addressableId != null ? [addressableId] : null,
    pTags: [pubkey],
  );
}
