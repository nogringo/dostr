# dostr_nip59

[NIP-59](https://github.com/nostr-protocol/nips/blob/master/59.md) gift wrap for Nostr: create rumors, seal them (kind `13`), wrap them with a one-time key (kind `1059`) and unwrap them back.

## Standalone

```yaml
dependencies:
  dostr_nip59: ^0.1.0
  dostr_bip340: ^0.1.0
```

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip59/dostr_nip59.dart';

final giftWrap = GiftWrap(
  signer: () => mySigner,
  eventVerifier: Bip340EventVerifier(),
  signerFactory: const Bip340SignerFactory(),
);

final rumor = giftWrap.createRumor(content: 'hello', kind: 14, tags: []);
final wrap = await giftWrap.toGiftWrap(rumor: rumor, recipientPubkey: pubkey);
final received = await giftWrap.fromGiftWrap(giftWrap: wrap);
```

`signer` is read on each call, so it can follow whoever is logged in, for example `() => accounts.getLoggedAccount()?.signer` with [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).
Every method also takes a `customSigner`.

The wrap is a signed kind `1059` event: publish it with the `RelayPublishes` of [`dostr_core`](https://pub.dev/packages/dostr_core), for example to the recipient's DM relays that `UrlSet.dm` of [`dostr_url_set`](https://pub.dev/packages/dostr_url_set) resolves to.

More in [example/](example/).

## API

- `createRumor`: an unsigned event, as the signer's pubkey unless `customPubkey` is given.
- `sealRumor` and `unsealRumor`: the kind `13` seal, signed by the sender.
- `wrapEvent` and `unwrapEvent`: the kind `1059` wrap of a seal, signed by a one-time key.
- `toGiftWrap`: seals the rumor and wraps the seal for `recipientPubkey`. The seal and the wrap get a `created_at` up to two days before the rumor's. `additionalTags` go on the wrap after its `p` tag, such as a NIP-40 `expiration`.
- `fromGiftWrap`: unwraps a kind `1059` and returns the rumor. Unless `verifySignature` is false, it checks the seal's signature, and that the rumor is from the seal's signer and matches its id.
- `fromGiftWrapWithInfo`: unwraps without throwing on a bad signature, and returns the seal, the rumor and whether each signature is valid.

## Errors

What cannot be wrapped or opened throws a `GiftWrapException`:

- `GiftWrapDecryptionException`: the signer cannot decrypt the wrap or the seal, because it is for someone else or because the signer failed. `cause` holds what the signer threw.
- `InvalidGiftWrapException`: the wrap decrypts but holds no valid seal and rumor. A payload is not an event, the seal's signature is wrong, or the rumor is not the seal signer's or does not match its id. `fromGiftWrapWithInfo` reports the last three instead of throwing.
- `GiftWrapEncryptionException`: the signer cannot encrypt for the recipient.
- `GiftWrapNoSignerException`: the call has no `customSigner` (or `customPubkey` for `createRumor`), and `signer` returns null.

A `SignerRequestException` of the signer, rejected or cancelled, passes through unchanged.
An event that is not a kind `1059` throws an `ArgumentError`.

## Fetching the wraps

A wrap is dated up to two days before its rumor, so a filter with `since: lastSeen` misses the messages sent after `lastSeen` whose wrap is dated before it.
Move `since` two days back, and order the messages by the rumor's `created_at`, never the wrap's:

```dart
final filter = Filter(
  kinds: [GiftWrap.kGiftWrapEventKind],
  pTags: [myPubkey],
  since: lastSeen - 2 * 24 * 60 * 60,
);
```

The overlap brings back wraps you already opened: a cache spares decrypting them again.

## Caching the plaintext

Without a cache, every unwrap asks the signer to decrypt again, which is slow with a remote signer.
Pass a `GiftWrapCache` as `cache`: it keeps the decrypted plaintext of each wrap and seal, per event id and viewer pubkey.
Later unwraps reuse it, and `tryFromGiftWrapFromCache` answers from the cache alone, or null when a payload is missing.

`GiftWrapCache` is an interface: implement `loadCachedPlaintext` and `loadOrDecrypt` on your storage.

## Deleting a gift wrap

The wrap is signed by a one-time key, so its author cannot delete it.
NIP-59 hands that to the recipient: relays should delete a kind `1059` whose `p` tag matches the signer of a NIP-09 deletion (kind `5`) or a NIP-62 vanish request.
Target the wrap id, the only id a relay holds: the rumor id is never published.

## Coming from `ndk`

`ndk.giftWrap` and the deep import `package:ndk/domain_layer/usecases/gift_wrap/gift_wrap.dart` become a `GiftWrap` from `package:dostr_nip59/dostr_nip59.dart`.

What changed:

| `ndk` | `dostr_nip59` |
|-------|---------------|
| `accounts` | `signer`, a function that returns the signer to use, or null |
| `eventSignerFactory` | `signerFactory` |
| `decryptedEventPayloads`, required | `cache`, an optional `GiftWrapCache` |
| `recipientPublicKey` of `wrapEvent` | `recipientPubkey` |
| `kGiftWrapEventkind` | `kGiftWrapEventKind` |
| `createRumor` returned a `Future` | returns the rumor |
| the static `GiftWrap.wrapEvent(eventSignerFactory: ...)` | `giftWrap.wrapEvent(...)`, with the `signerFactory` of `GiftWrap` |
| `toGiftWrap` put no other tag than `p` on the wrap | takes `additionalTags` |
| a bare `Exception` | a `GiftWrapException`, or an `ArgumentError` for an event that is not a kind `1059` |
| the `sig` of a signed rumor went into its seal | is left out |
