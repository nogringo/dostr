# ndk_nip13

[NIP-13](https://github.com/nostr-protocol/nips/blob/master/13.md) proof of work for Nostr events: mine an event until its id has enough leading zero bits, read the difficulty of an id, and check an event against the target its `nonce` tag commits to.

Mining runs in its own isolate (on the main thread on the web). It does not depend on `ndk`.

## Install

```yaml
dependencies:
  ndk_nip13: ^0.1.0
```

## Usage

```dart
import 'package:ndk_nip13/ndk_nip13.dart';

final mined = await Nip13.mineEvent(event, 20);
Nip13.getDifficulty(mined.id); // >= 20
Nip13.validateEvent(mined); // true

await ndk.broadcast.broadcast(nostrEvent: mined);
```

`mineEvent` adds a `nonce` tag (replacing any existing one) and returns an unsigned event, since the id changes with the nonce. Sign it after mining: `ndk.broadcast` does it with the logged-in account. It throws after `maxIterations` tries, 1,000,000 by default.

## Coming from `ndk`

`ndk.proofOfWork` and the `ProofOfWork` usecase are gone. Use the static methods of `Nip13`:

| Before | After |
| ------ | ----- |
| `ndk.proofOfWork.minePoW(event: e, targetDifficulty: d)` | `Nip13.mineEvent(e, d)` |
| `ndk.proofOfWork.getPoWDifficulty(e)` | `Nip13.getDifficulty(e.id)` |
| `ndk.proofOfWork.checkPoWDifficulty(event: e, targetDifficulty: d)` | `Nip13.checkDifficulty(e.id, d)` |
| `ndk.proofOfWork.getTargetDifficultyFromEvent(e)` | `Nip13.getTargetDifficultyFromEvent(e)` |
| `ndk.proofOfWork.powCommitment(e)` | `Nip13.calculateCommitment(e.id)`, now a `BigInt` |

`package:ndk/shared/nips/nip13/nip13.dart` is now `package:ndk_nip13/ndk_nip13.dart`.
