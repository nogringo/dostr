# dostr_web_crypto

Fast [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki) Schnorr signatures for Nostr events on the web: a `NostrSigner` that holds a private key, its `LocalSignerFactory`, and an `EventVerifier`.
They call [@noble/curves](https://github.com/paulmillr/noble-curves) through JS interop, which is much faster than pure Dart in the browser.
The signer also does NIP-04 and NIP-44 encryption.
Everything runs on @noble, without the Web Crypto API, so it also works on a page served over plain http, such as a phone opening the app on the local network.

Pure Dart, no Flutter needed.
The JS bundle is embedded and injected into the page the first time a class needs it, so there is nothing to add to `index.html`.

[`dostr_flutter`](https://pub.dev/packages/dostr_flutter) depends on it and exports it, so Flutter apps that already use `dostr_flutter` don't need to add it.

## Install

```yaml
dependencies:
  dostr_web_crypto: ^0.1.0
```

## Usage

```dart
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';

final signer = const WebSignerFactory().createWithNewKeyPair();
final event = await signer.sign(
  Nip01Event(
    pubkey: signer.publicKey,
    kind: 1,
    tags: [],
    content: 'hello nostr',
  ),
);

final valid = await const WebEventVerifier().verify(event);
```

`WebSigner(privateKey)` signs with a key you hold and derives its public key, and `WebSigner.readOnly(publicKey)` is an account that only reads.

The classes only work on the web.
On other platforms they throw `UnsupportedError`: use `dostr_bip340`, or `RustEventVerifier` from `dostr_rust_verifier`.

## Content Security Policy

The bundle is injected as an inline script.
A `Content-Security-Policy` whose `script-src` does not allow `'unsafe-inline'` blocks it, and Trusted Types (`require-trusted-types-for 'script'`) make the injection throw, so the classes throw on first use.
On such a page, serve the `js/nostr_crypto.js` of the version you depend on, and load it before the app:

```html
<script src="nostr_crypto.js"></script>
```

The classes then use the `DostrWebCrypto` it defines and inject nothing.
Copy the file again on every upgrade of `dostr_web_crypto`, since it must match the Dart side: when it does not, the classes throw a `StateError` that gives both versions.

A Web Worker has no page to inject the bundle into, so the classes are not supported there.

## Coming from `ndk_flutter`

`WebEventVerifier` moved here from `ndk_flutter`, and so did `WebEventSigner`, now `WebSigner`.
`WebEventSigner(privateKey: ..., publicKey: ...)` is now `WebSigner(privateKey)`, and `WebEventSigner(privateKey: null, publicKey: ...)` is now `WebSigner.readOnly(publicKey)`.
`package:ndk_flutter/ndk_flutter.dart` is now `package:dostr_flutter/dostr_flutter.dart`, which still exports them.
The web `NdkEventSignerFactory` of `ndk_flutter` is now `DostrSignerFactory`, a typedef of `WebSignerFactory`.

## Rebuilding the JS bundle

`lib/src/nostr_crypto_js.dart` is generated from `js/nostr_crypto.src.js`.
To rebuild it, run `npm ci`, then `./build.sh`, in `js/`.
`js/package-lock.json` pins the @noble versions the committed bundle was built with.
`build.sh` stamps the bundle with a hash of the files it is built from, which is the version the classes check.
The CI rebuilds the bundle and fails when it differs from the committed one, so the committed bundle is the one its sources build.
