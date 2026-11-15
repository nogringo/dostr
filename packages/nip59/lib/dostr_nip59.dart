/// NIP-59 gift wrap for Nostr.
///
/// ```dart
/// final giftWrap = GiftWrap(
///   signer: () => signer,
///   eventVerifier: verifier,
///   signerFactory: const Bip340SignerFactory(),
/// );
/// final wrap = await giftWrap.toGiftWrap(rumor: rumor, recipientPubKey: pubkey);
/// ```
library;

export 'src/gift_wrap.dart';
export 'src/gift_wrap_cache.dart';
export 'src/gift_wrap_exceptions.dart';
export 'src/gift_wrap_unwrap_result.dart';
