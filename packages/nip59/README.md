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
  eventSignerFactory: const Bip340EventSignerFactory(),
);

final rumor = await giftWrap.createRumor(content: 'hello', kind: 14, tags: []);
final wrap = await giftWrap.toGiftWrap(rumor: rumor, recipientPubkey: pubkey);
final received = await giftWrap.fromGiftWrap(giftWrap: wrap);
```

`signer` is read on each call, so it can follow whoever is logged in, for example `() => accounts.getLoggedAccount()?.signer` with [`dostr_accounts`](https://pub.dev/packages/dostr_accounts). Every method also takes a `customSigner`.

The wrap is a signed kind `1059` event: publish it with the `RelayPublishes` of [`dostr_core`](https://pub.dev/packages/dostr_core), for example to the recipient's DM relays that `UrlSet.dm` of [`dostr_url_set`](https://pub.dev/packages/dostr_url_set) resolves to.

More in [example/](example/).

## API

- `createRumor`: an unsigned event, as the signer's pubkey unless `customPubkey` is given.
- `sealRumor` and `unsealRumor`: the kind `13` seal, signed by the sender.
- `toGiftWrap`: seals the rumor and wraps the seal for `recipientPubkey`. The seal and the wrap get a `created_at` up to two days before the rumor's.
- `fromGiftWrap`: unwraps a kind `1059` and returns the rumor. Unless `verifySignature` is false, it checks the seal's signature, and that the rumor is from the seal's signer and matches its id.
- `fromGiftWrapWithInfo`: unwraps without throwing on a bad signature, and returns the seal, the rumor and whether each signature is valid.

## Caching the plaintext

Without a cache, every unwrap asks the signer to decrypt again, which is slow with a remote signer. Pass a `GiftWrapCache` as `cache`: it keeps the decrypted plaintext of each wrap and seal, per event id and viewer pubkey. Later unwraps reuse it, and `tryFromGiftWrapFromCache` answers from the cache alone, or null when a payload is missing.

`GiftWrapCache` is an interface: implement `loadCachedPlaintext` and `loadOrDecrypt` on your storage.

## Deleting a gift wrap

The wrap is signed by a one-time key, so its author cannot delete it. NIP-59 hands that to the recipient: relays should delete a kind `1059` whose `p` tag matches the signer of a NIP-09 deletion (kind `5`) or a NIP-62 vanish request. Target the wrap id, the only id a relay holds: the rumor id is never published.
