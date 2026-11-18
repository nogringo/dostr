import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import 'invoice_response.dart';
import 'lnurl.dart';
import 'logger.dart';
import 'zap_receipt.dart';
import 'zap_request.dart';

/// The events relays hold for [filter], as they arrive, each with a verified
/// signature, as `RelayReqs` of `dostr_core` gives them. The stream ends once
/// the relays are done or [timeout] runs out.
typedef ZapsQuery =
    Stream<Nip01Event> Function(Filter filter, {required Duration timeout});

/// A live subscription: the [events] it receives, each with a verified
/// signature, and [close] to end it.
typedef ZapsSubscription = ({
  Stream<Nip01Event> events,
  Future<void> Function() close,
});

/// Opens a live subscription to [filter].
typedef ZapsSubscribe = ZapsSubscription Function(Filter filter);

/// A live subscription to zap receipts: the valid [receipts] it receives, and
/// [close] to end it.
typedef ZapReceiptsSubscription = ({
  Stream<ZapReceipt> receipts,
  Future<void> Function() close,
});

/// NIP-57 zaps: zap requests, the invoices that carry them, and the zap
/// receipts of a recipient.
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

  /// The invoice of [amountSats] that the LNURL-pay server at [lud16Link]
  /// issues, or null when the server cannot be reached or gives none.
  ///
  /// The invoice carries [zapRequest] when the server allows Nostr and
  /// [zapRequest] is signed, and [comment] when the server takes comments.
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
      logger.fine(() => e);
      return null;
    }
  }

  /// A zap request of [amountSats] to [pubkey], signed by [signer], that asks
  /// the recipient's LNURL server to publish its receipt to [relays].
  ///
  /// [eventId] or [addressableId] zaps an event rather than a profile,
  /// [comment] is the sender's message, and [pollOption] votes in a zap poll.
  /// Throws an [ArgumentError] when [amountSats] is negative.
  Future<ZapRequest> createZapRequest({
    required int amountSats,
    required NostrSigner signer,
    required String pubkey,
    String? eventId,
    String? addressableId,
    String? comment,
    required Iterable<RelayUrl> relays,
    String? pollOption,
  }) async {
    if (amountSats < 0) {
      throw ArgumentError.value(
        amountSats,
        'amountSats',
        'must not be negative',
      );
    }
    final zapRequest = ZapRequest(
      pubkey: signer.publicKey,
      tags: [
        ['relays', ...relays],
        ['amount', '${amountSats * 1000}'],
        ['p', pubkey],
        if (eventId != null) ['e', eventId],
        if (addressableId != null) ['a', addressableId],
        if (pollOption != null) ['poll_option', pollOption],
      ],
      content: comment ?? '',
    );
    return ZapRequest.nip01Event(event: await signer.sign(zapRequest));
  }

  /// The valid receipts of the zaps to [pubkey], as they arrive. The stream
  /// ends once the relays are done or [timeout] runs out.
  ///
  /// [nostrPubkey] is the `nostrPubkey` of the recipient's LNURL server, from
  /// its [LnurlResponse]. Only receipts it signed are asked for, and only
  /// those that pass [ZapReceipt.isValid] with it and [recipientLnurl] come
  /// out. Receipts from a server the recipient left are not valid anymore.
  ///
  /// Pass [eventId] or [addressableId] for the zaps of one event.
  Stream<ZapReceipt> fetchZappedReceipts({
    required String pubkey,
    required String nostrPubkey,
    String? recipientLnurl,
    String? eventId,
    String? addressableId,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final filter = _receiptsFilter(
      pubkey: pubkey,
      nostrPubkey: nostrPubkey,
      eventId: eventId,
      addressableId: addressableId,
    );
    return _validReceipts(
      _query(filter, timeout: timeout),
      filter: filter,
      nostrPubkey: nostrPubkey,
      recipientLnurl: recipientLnurl,
    );
  }

  /// The valid receipts of the zaps to [pubkey] that arrive until the
  /// subscription is closed, as [fetchZappedReceipts] picks them.
  ZapReceiptsSubscription subscribeToZapReceipts({
    required String pubkey,
    required String nostrPubkey,
    String? recipientLnurl,
    String? eventId,
    String? addressableId,
  }) {
    final filter = _receiptsFilter(
      pubkey: pubkey,
      nostrPubkey: nostrPubkey,
      eventId: eventId,
      addressableId: addressableId,
    );
    final subscription = _subscribe(filter);
    return (
      receipts: _validReceipts(
        subscription.events,
        filter: filter,
        nostrPubkey: nostrPubkey,
        recipientLnurl: recipientLnurl,
      ),
      close: subscription.close,
    );
  }

  static Filter _receiptsFilter({
    required String pubkey,
    required String nostrPubkey,
    required String? eventId,
    required String? addressableId,
  }) => Filter(
    kinds: [ZapReceipt.kKind],
    authors: [nostrPubkey],
    eTags: eventId != null ? [eventId] : null,
    aTags: addressableId != null ? [addressableId] : null,
    pTags: [pubkey],
  );

  static Stream<ZapReceipt> _validReceipts(
    Stream<Nip01Event> events, {
    required Filter filter,
    required String nostrPubkey,
    required String? recipientLnurl,
  }) => events
      .where(filter.matches)
      .map(ZapReceipt.fromEvent)
      .where(
        (receipt) => receipt.isValid(
          nostrPubkey: nostrPubkey,
          recipientLnurl: recipientLnurl,
        ),
      );
}
