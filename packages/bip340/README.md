# dostr_bip340

[BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki)
Schnorr signatures for Nostr events, in pure Dart: an `EventSigner` that holds a
private key, an `EventVerifier`, and the `Bip340` helpers under them.

[NDK](https://pub.dev/packages/ndk) depends on it and exports it, so apps that
already use `ndk` don't need to add it. Add it next to
[`dostr_core`](https://pub.dev/packages/dostr_core) when you use the core on its own.

## Install

```yaml
dependencies:
  dostr_bip340: ^0.1.0
```

## Usage

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

final signer = Bip340EventSignerFactory().createWithNewKeyPair();
final event = await signer.sign(
  Nip01Event(
    pubKey: signer.getPublicKey(),
    kind: 1,
    tags: [],
    content: 'hello nostr',
  ),
);

final valid = await Bip340EventVerifier().verify(event);
```

`Bip340EventVerifier` verifies on the calling isolate. On mobile, the Rust
verifier of `dostr_rust_verifier` is much faster.

## Coming from `ndk` or `dostr_core`

`package:dostr_core/shared/nips/nip01/bip340.dart` and the
`Bip340EventSigner` and `Bip340EventVerifier` files are now all in
`package:dostr_bip340/dostr_bip340.dart`. `Nip01Utils.signWithPrivateKey` is now
`Bip340.signEvent`. `package:ndk/ndk.dart` still exports all of it.
