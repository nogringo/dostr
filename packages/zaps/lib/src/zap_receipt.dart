import 'dart:convert';

import 'package:dostr_nip01/dostr_nip01.dart';

import 'bolt11.dart';
import 'zap_request.dart';

/// A NIP-57 zap receipt: the event of kind [kKind] that the recipient's LNURL
/// server publishes once the invoice of a zap request is paid.
///
/// Anyone can publish one, see [isValid].
final class ZapReceipt {
  static const kKind = 9735;

  /// the LNURL server that signed the receipt
  final String pubkey;

  /// when the invoice was paid, in seconds since the epoch
  final int paidAt;

  /// the paid invoice, from the `bolt11` tag
  final String? bolt11;

  /// the amount of [bolt11], in millisats
  final int? amountMsats;

  /// the preimage of [bolt11], which proves nothing (NIP-57)
  final String? preimage;

  /// the pubkey of the recipient, from the `p` tag
  final String? recipient;

  /// the zapped event, from the `e` tag
  final String? eventId;

  /// the `anon` tag, as the receipt has it
  final String? anon;

  /// the zap request the invoice was for, from the `description` tag
  final ZapRequest? zapRequest;

  const ZapReceipt._({
    required this.pubkey,
    required this.paidAt,
    required this.bolt11,
    required this.amountMsats,
    required this.preimage,
    required this.recipient,
    required this.eventId,
    required this.anon,
    required this.zapRequest,
  });

  /// The receipt [event] holds, whatever its tags.
  ///
  /// Throws an [ArgumentError] when [event] is not of kind [kKind].
  factory ZapReceipt.fromEvent(Nip01Event event) {
    if (event.kind != kKind) {
      throw ArgumentError.value(
        event.kind,
        'event.kind',
        'is not a zap receipt ($kKind)',
      );
    }
    final bolt11 = event.getFirstTag('bolt11');
    return ZapReceipt._(
      pubkey: event.pubkey,
      paidAt: event.createdAt,
      bolt11: bolt11,
      amountMsats: bolt11 == null ? null : bolt11AmountMsats(bolt11),
      preimage: event.getFirstTag('preimage'),
      recipient: event.getFirstTag('p'),
      eventId: event.getFirstTag('e'),
      anon: event.getFirstTag('anon'),
      zapRequest: _zapRequestOf(event.getFirstTag('description')),
    );
  }

  /// [amountMsats] in sats, rounded
  int? get amountSats => switch (amountMsats) {
    final int msats => (msats / 1000).round(),
    null => null,
  };

  /// the pubkey of the sender, who signed [zapRequest]
  String? get sender => zapRequest?.pubkey;

  /// the sender's message, the content of [zapRequest]
  String? get comment => zapRequest?.content;

  /// the `lnurl` tag of [zapRequest]
  String? get lnurl => zapRequest?.getFirstTag('lnurl');

  /// Whether the receipt passes the checks of NIP-57 (appendix F) for a
  /// recipient whose LNURL server signs with [nostrPubkey]:
  /// - [nostrPubkey] signed it, and it names the recipient of [zapRequest].
  /// - [bolt11] has an amount, the `amount` of [zapRequest] when it has one.
  /// - The `lnurl` of [zapRequest] is [recipientLnurl], ignoring case, when
  ///   both are there.
  ///
  /// Checking the receipt's signature is left to the caller. A valid receipt
  /// proves that the server says the invoice was paid, not that it was.
  bool isValid({required String nostrPubkey, String? recipientLnurl}) {
    final zapRequest = this.zapRequest;
    if (pubkey != nostrPubkey || zapRequest == null || amountMsats == null) {
      return false;
    }
    if (recipient == null || zapRequest.getFirstTag('p') != recipient) {
      return false;
    }
    if (zapRequest.getFirstTag('amount') case final String amount
        when int.tryParse(amount) != amountMsats) {
      return false;
    }
    if ((lnurl, recipientLnurl) case (
      final String requested,
      final String expected,
    ) when requested.toLowerCase() != expected.toLowerCase()) {
      return false;
    }
    return true;
  }

  static ZapRequest? _zapRequestOf(String? description) {
    if (description == null) return null;
    try {
      return switch (Nip01Event.tryFromJson(jsonDecode(description))) {
        final Nip01Event event when event.kind == ZapRequest.kZapRequestKind =>
          ZapRequest.nip01Event(event: event),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() =>
      'ZapReceipt(pubkey: $pubkey, paidAt: $paidAt, amountMsats: $amountMsats, recipient: $recipient, eventId: $eventId, sender: $sender, comment: $comment)';
}
