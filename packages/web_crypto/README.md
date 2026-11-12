# ndk_web_crypto

Fast [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki)
Schnorr signatures for Nostr events on the web: an `EventSigner` that holds a
private key, its `LocalEventSignerFactory`, and an `EventVerifier`. They call
[@noble/curves](https://github.com/paulmillr/noble-curves) through JS interop,
which is much faster than pure Dart in the browser. The signer also does NIP-04
and NIP-44 encryption.

Pure Dart, no Flutter needed. The JS bundle is embedded and injected into the
page the first time a class needs it, so there is nothing to add to
`index.html`.

[`ndk_flutter`](https://pub.dev/packages/ndk_flutter) depends on it and exports
it, so Flutter apps that already use `ndk_flutter` don't need to add it.

## Install

```yaml
dependencies:
  ndk_web_crypto: ^0.1.0
```

## Usage

```dart
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_web_crypto/ndk_web_crypto.dart';

final signer = const WebEventSignerFactory().createWithNewKeyPair();
final event = await signer.sign(
  Nip01Event(
    pubKey: signer.getPublicKey(),
    kind: 1,
    tags: [],
    content: 'hello nostr',
  ),
);

final valid = await WebEventVerifier().verify(event);
```

The classes only work on the web. On other platforms they throw
`UnsupportedError`: use `ndk_bip340`, or `RustEventVerifier` from
`ndk_rust_verifier`.

## Coming from `ndk_flutter`

`WebEventSigner` and `WebEventVerifier` moved here from `ndk_flutter`, which
still exports them from `package:ndk_flutter/ndk_flutter.dart`. The web
`NdkEventSignerFactory` of `ndk_flutter` is now a typedef of
`WebEventSignerFactory`.

## Rebuilding the JS bundle

`lib/src/nostr_crypto_js.dart` is generated from `js/nostr_crypto.src.js`. To
rebuild it, run `npm install`, then `./build.sh`, in `js/`.
