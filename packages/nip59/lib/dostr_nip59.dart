/// NIP-59 gift wrap for Nostr.
///
/// ```dart
/// final giftWrap = GiftWrap(
///   signer: () => signer,
///   eventVerifier: verifier,
///   eventSignerFactory: const Bip340EventSignerFactory(),
/// );
/// final wrap = await giftWrap.toGiftWrap(rumor: rumor, recipientPubkey: pubkey);
/// ```
library;

export 'src/domain_layer/entities/gift_wrap_unwrap_result.dart';
export 'src/domain_layer/repositories/gift_wrap_cache.dart';
export 'src/domain_layer/usecases/gift_wrap/gift_wrap.dart';
