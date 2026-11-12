import 'package:dostr_nip01/dostr_nip01.dart';

/// Result of unwrapping a gift wrap with signature verification
class GiftWrapUnwrapResult {
  /// Whether the outer gift-wrap event has a valid signature.
  final bool isGiftWrapSignatureValid;

  /// Whether the seal event has a valid signature
  final bool isSealSignatureValid;

  /// The outer gift-wrap event (kind:1059).
  final Nip01Event giftWrap;

  /// The seal event (kind:13) extracted from the gift wrap
  final Nip01Event seal;

  /// The rumor event extracted from the seal
  final Nip01Event rumor;

  GiftWrapUnwrapResult({
    required this.isGiftWrapSignatureValid,
    required this.isSealSignatureValid,
    required this.giftWrap,
    required this.seal,
    required this.rumor,
  });

  /// Whether the seal's pubkey matches the rumor's pubkey
  bool get isPubkeyMatch => seal.pubKey == rumor.pubKey;

  /// Whether the rumor's id matches its content
  bool get isRumorIdValid => rumor.hasValidId;

  /// Whether both signed layers are valid and bind the rumor, untouched, to
  /// its author.
  bool get isCryptographicallyValid =>
      isGiftWrapSignatureValid &&
      isSealSignatureValid &&
      isPubkeyMatch &&
      isRumorIdValid;
}
