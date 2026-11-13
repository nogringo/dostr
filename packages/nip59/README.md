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

`signer` is read on each call, so it can follow whoever is logged in; every method also takes a `customSigner`. Pass a `GiftWrapCache` as `cache` to keep decrypted seals and rumors, so later unwraps skip the signer and `tryFromGiftWrapFromCache` can answer without it.

More in [example/](example/) and the [gift wrap docs](https://nogringo.github.io/dostr/usecases/gift-wrap/).
