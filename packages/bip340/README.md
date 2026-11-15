# dostr_bip340

[BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki)
Schnorr signatures for Nostr events, in pure Dart: a `NostrSigner` that holds a
private key, an `EventVerifier`, and the `Bip340` helpers under them.

Add it next to [`dostr_core`](https://pub.dev/packages/dostr_core) to sign and
verify events.

## Install

```yaml
dependencies:
  dostr_bip340: ^0.1.0
```

## Usage

```dart
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

final signer = Bip340SignerFactory().createWithNewKeyPair();
final event = await signer.sign(
  Nip01Event(
    pubkey: signer.getPublicKey(),
    kind: 1,
    tags: [],
    content: 'hello nostr',
  ),
);

final valid = await Bip340EventVerifier().verify(event);
```

`Bip340EventVerifier` verifies on the calling isolate. On mobile, the Rust
verifier of `dostr_rust_verifier` is much faster.

## Coming from `ndk`

`package:ndk/shared/nips/nip01/bip340.dart` and the
`Bip340EventSigner` and `Bip340EventVerifier` files are now all in
`package:dostr_bip340/dostr_bip340.dart`. `Bip340EventSigner` and
`Bip340EventSignerFactory` are now `Bip340Signer` and `Bip340SignerFactory`.
`Nip01Utils.signWithPrivateKey` is now `Bip340.signEvent`.
