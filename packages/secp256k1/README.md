# dostr_secp256k1

The secp256k1 curve in pure Dart, with no Nostr in it: the point arithmetic and the [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki) Schnorr signatures under [`dostr_bip340`](https://pub.dev/packages/dostr_bip340), the [NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md) key agreement of [`dostr_nip44`](https://pub.dev/packages/dostr_nip44) and the blind signatures of [`dostr_cashu_protocol`](https://pub.dev/packages/dostr_cashu_protocol).

To sign Nostr events or encrypt, use those packages: they take keys in hex.
Add this one on its own to work with bytes and curve points directly, or to build another scheme on the curve.

## Install

```yaml
dependencies:
  dostr_secp256k1: ^0.1.0
```

## Schnorr signatures

```dart
import 'package:dostr_secp256k1/dostr_secp256k1.dart';

final publicKey = Schnorr.publicKey(privateKey);
final signature = Schnorr.sign(message, privateKey);
final valid = Schnorr.verify(message, signature, publicKey);
```

Keys are 32 bytes, the public key x-only, and signatures 64 bytes.
A message can have any length.
`Schnorr.verify` returns false, and never throws, on malformed input.

## Points

```dart
final alice = BigInt.parse(alicePrivateKey, radix: 16);
final bob = BigInt.parse(bobPrivateKey, radix: 16);

final alicePublicKey = (Secp256k1Point.generator * alice).x;
final bobPublicKey = (Secp256k1Point.generator * bob).x;

// ECDH: both sides get the same x
final fromAlice = (Secp256k1Point.fromX(bobPublicKey)! * alice).x;
final fromBob = (Secp256k1Point.fromX(alicePublicKey)! * bob).x;
```

`Secp256k1Point.fromX` lifts an x to the point with an even y, as BIP-340 `lift_x` does, `fromXY` checks a full point, and `fromSec1` decodes a compressed or uncompressed SEC1 key.
They return null for a point that is not on the curve.
`toSec1` encodes a point back, and `+`, `-` and `*` do the group arithmetic, with `Secp256k1Point.infinity` as the identity.

## Performance

The arithmetic runs in Jacobian coordinates, so a multiplication inverts only once: `x` and `y` are computed on first read.
Multiplying `Secp256k1Point.generator` goes through a table of 960 of its multiples in affine coordinates, built on first use in a few milliseconds.
Multiplying any other point splits the scalar in two halves of 128 bits with the GLV endomorphism of the curve, which halves the doublings.

On an Apple Silicon laptop, compiled ahead of time, `generator * k` takes about 0.1 ms and `point * k` about 0.29 ms, against about 2.7 ms for the pointycastle curve.
A Schnorr signature takes about 0.23 ms and a verification about 0.45 ms.

None of it runs in constant time.
