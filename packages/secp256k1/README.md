# dostr_secp256k1

The secp256k1 curve for Nostr, in pure Dart: the point arithmetic under the [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki) signatures of [`dostr_bip340`](https://pub.dev/packages/dostr_bip340) and the [NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md) key agreement of [`dostr_nip44`](https://pub.dev/packages/dostr_nip44).

To sign, verify or encrypt, use those two packages.
Add this one on its own when you need curve points directly, to derive keys or to build another scheme on the curve.

## Install

```yaml
dependencies:
  dostr_secp256k1: ^0.1.0
```

## Usage

```dart
import 'package:dostr_secp256k1/dostr_secp256k1.dart';

final alice = BigInt.parse(alicePrivateKey, radix: 16);
final bob = BigInt.parse(bobPrivateKey, radix: 16);

// x-only public keys, as in Nostr events
final alicePublicKey = (Secp256k1Point.generator * alice).x;
final bobPublicKey = (Secp256k1Point.generator * bob).x;

// ECDH: both sides get the same x
final fromAlice = (Secp256k1Point.fromX(bobPublicKey)! * alice).x;
final fromBob = (Secp256k1Point.fromX(alicePublicKey)! * bob).x;
```

`Secp256k1Point.fromX` lifts an x to the point with an even y, as BIP-340 `lift_x` does, and `fromXY` checks a full point.
Both return null for a point that is not on the curve.

## Performance

The arithmetic runs in Jacobian coordinates, so a multiplication inverts only once: `x` and `y` are computed on first read.
Multiplying `Secp256k1Point.generator` goes through a table of 960 of its multiples, built on first use in a few milliseconds.

On an Apple Silicon laptop, compiled ahead of time, `generator * k` takes about 0.13 ms and `point * k` about 0.42 ms, against about 2.7 ms for the pointycastle curve.

None of it runs in constant time.
```
