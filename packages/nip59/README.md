# ndk_nip59

[NIP-59](https://github.com/nostr-protocol/nips/blob/master/59.md) gift wrap for [NDK](https://pub.dev/packages/ndk): create rumors, seal them (kind `13`), wrap them with a one-time key (kind `1059`) and unwrap them back. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package and exposes it as `ndk.giftWrap`, wired to the logged-in account and to the decrypted payload cache:

```dart
import 'package:ndk/ndk.dart';

final wrap = await ndk.giftWrap.toGiftWrap(rumor: rumor, recipientPubkey: pubkey);
final received = await ndk.giftWrap.fromGiftWrap(giftWrap: wrap);
```

## Standalone

```yaml
dependencies:
  ndk_nip59: ^0.1.0
  ndk_bip340: ^0.1.0
```

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_nip59/ndk_nip59.dart';

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

More in [example/](example/) and the [gift wrap docs](https://dart-nostr.com/usecases/gift-wrap/).
